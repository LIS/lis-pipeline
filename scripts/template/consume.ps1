

#From AzureWinUtils (with a lot removed)
function LogMsg([string]$msg, [string]$color="green")
{
    # #Masking the password.
    # $pass2 = $password.Replace('"','')
    # $msg = $msg.Replace($pass2,"$($pass2[0])***$($pass2[($pass2.Length) - 1])")
    foreach ( $line in $msg )
    {
        $now = [Datetime]::Now.ToUniversalTime().ToString("MM/dd/yyyy HH:mm:ss : ")
        $tag="INFO : "
        write-host -f $color "$tag $now $line"
    }
}

# Import-Module ..\ConvertFrom-ArbritraryXml.psm1
# $xmlAsText = Get-Content -Path .\Make_Drone.xml
# $ob = ConvertFrom-ArbritraryXml( [xml] $xmlAsText )
# $json = $ob | ConvertTo-Json -Depth 10

$jsonAsText =  Get-Content -Path .\deploy_drone.json | Out-String
$json = ConvertFrom-Json $jsonAsText 

LogMsg "Building Topology $($json.Topology.Name)" "cyan"

#TODO: Security Groups could be multiple.
#LogMsg "Checking to see if security group exists already."
LogMsg "Using ResourceGroup :: $($json.Topology.ResourceGroup)"

$rg = Get-AzureRmResourceGroup `
  -Name $json.Topology.ResourceGroup `
  -ErrorAction Ignore
  if( $null -ne $rg )
  {
    #TODO: Purge option.
    LogMsg "Found existing resource group. Deleting." "yellow"
    Remove-AzureRmResourceGroup -Name $json.Topology.ResourceGroup -Force 
    LogMsg "Complete."
  }
  LogMsg "Creating resource group." 
  $rg = New-AzureRmResourceGroup `
    -Name $json.Topology.ResourceGroup `
    -Location $json.Topology.Location
    #TODO: ErrorAction
  LogMsg "Completed creating ResourceGroup:$($json.Topology.ResourceGroup)."

LogMsg "Creating security groups" "magenta"  #TODO: More than one.
$sg = Get-AzureRmNetworkSecurityGroup `
 -Name $json.Topology.NetworkSecurityGroup.Name `
 -ResourceGroupName $json.Topology.ResourceGroup `
 -ErrorAction Ignore
 if( $null -ne $sg )
 {
   LogMsg "This should never happen.", "red"
 }
 else {
   $rules = @()
   foreach( $def in $json.Topology.NetworkSecurityGroup.Rule )
   {
     LogMsg "Creating rule: $($def.Name) -- $($def.Description)"
     $rule = New-AzureRmNetworkSecurityRuleConfig `
     -Name $def.Name -Description $def.Description `
     -Access $def.Access -Protocol $def.Protocol -Direction $def.Direction `
     -Priority $def.Priority -SourceAddressPrefix $def.SourceAddressPrefix `
     -SourcePortRange $def.SourcePortRange  `
     -DestinationAddressPrefix $def.DestinationAddressPrefix `
     -DestinationPortRange $def.DestinationPortRange
     $rules += $rule
   }
   New-AzureRmNetworkSecurityGroup -Name $json.Topology.NetworkSecurityGroup.Name `
    -ResourceGroupName $json.Topology.ResourceGroup `
    -Location $json.Topology.Location `
    -SecurityRules $rules
   $sg = Get-AzureRmNetworkSecurityGroup `
   -Name $json.Topology.NetworkSecurityGroup.Name `
   -ResourceGroupName $json.Topology.ResourceGroup `
   -ErrorAction Ignore

   LogMsg "Now building the Network -- $($json.Topology.Network.Name)"
   $vnet = Get-AzureRmVirtualNetwork `
    -Name $json.Topology.Network.Name `
    -ResourceGroupName $json.Topology.ResourceGroup
    if ($null -eq $vnet) {
        LogMsg "Network does not exist for this region.  Creating now..." "yellow"
        write-host "Network does not exist for this region.  Creating now..." -ForegroundColor Yellow
        $vsubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $json.Topology.Network.Subnet.Name `
          -AddressPrefix $json.Topology.Network.Subnet.AddressPrefix -NetworkSecurityGroup $sg
        New-AzureRmVirtualNetwork  -Name $json.Topology.Network.Name `
          -ResourceGroupName $json.Topology.ResourceGroup -Location $json.Topology.Location `
          -AddressPrefix $json.Topology.Network.AddressPrefix -Subnet $vsubnet
          $vnet = Get-AzureRmVirtualNetwork -Name $json.Topology.Network.Name `
            -ResourceGroupName $json.Topology.ResourceGroup
    }
 }

 LogMsg "Now building the computers." "magenta"

foreach( $def in $json.Topology.VirtualMachine )
{
  LogMsg $def.Name "green"
  $vm = New-AzureRmVMConfig -VMName $def.Name -VMSize $def.VMSize
  LogMsg "Creating Public IP $($def.PublicNIC.PublicIP)"
  #TODO These checks don't make sense if I am creating from scratch.
  $pip = Get-AzureRmPublicIPAddress `
    -ResourceGroupName $json.Topology.ResourceGroup `
    -Name $def.NIC.PublicIPName `
    -ErrorAction Continue
  if( $null -eq $pip )
  {
    LogMsg "Building Public IP $($def.NIC.PublicIPName)"
    $pip = New-AzureRmPublicIPAddress `
      -ResourceGroupName $json.Topology.ResourceGroup `
      -Name $def.NIC.PublicIPName `
      -Location $json.Topology.Location `
      -AllocationMethod $def.NIC.Allocation  #TODO: Add option for DNSPrefix. 
    LogMsg "IP: $($pip.IpAddress)"
  }
  if( $null -eq $pip )
  {
    LogMsg "Unable to allocate PIP" "red"
  } 
  LogMsg "Creating NIC $($def.NIC.Name)"
  $nic = New-AzureRmNetworkInterface -Name $def.NIC.Name -ResourceGroupName $json.Topology.ResourceGroup `
    -Location $json.Topology.Location `
    -Subnet $vnet.Subnets[0] -PublicIpAddress $pip `
    -NetworkSecurityGroup $sg
  
  if( $null -eq $nic )
  {
    LogMsg "Unable to allocate NIC" "red"
    break
  }
  # Enable the NIC
  LogMsg "Enabling the NIC..."
  $nic | Set-AzureRmNetworkInterface 
  LogMsg "Adding the NIC to the VM"
  Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id
  LogMsg "Hooking up the hard drive..."
  Set-AzureRmVMOSDisk -VM $vm -Name $def.Name `
    -VhdUri $def.OSDisk.Uri -CreateOption $def.OSDisk.CreateOption `
    -Linux  #TODO Use my option instead of asserting this switch.

  if( $def.EnableBootDiagnostics -eq "Yes" )
  {
    LogMsg "Enabling Boot Diagnostics." "yellow"
    LogMsg "Really just doing nothing." "cyan"
  } else {
    LogMsg "Boot Diagnostics Disabled." "yellow"
    Set-AzureRmVMBootDiagnostics -VM $vm -Disable
  }
  LogMsg "Starting the VM..."
  $NewVM = New-AzureRmVM -ResourceGroupName $json.Topology.ResourceGroup `
    -Location $json.Topology.Location -VM $vm -ErrorAction continue

  if( $null -eq $NewVM )
  {
    LogMsg "Error occurred. Null result." "red"
  } else {
    LogMsg "Success: $($pip.IpAddress)"
  }
}

