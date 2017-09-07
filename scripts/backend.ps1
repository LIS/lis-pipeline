##### Install PowerShell 5 using https://github.com/DarwinJS/ChocoPackages/blob/master/PowerShell/v5.1/tools/ChocolateyInstall.ps1#L107-L173
##### For 2008 R2, run the .ps1 from: https://download.microsoft.com/download/6/F/5/6F5FF66C-6775-42B0-86C4-47D41F2DA187/Win7AndW2K8R2-KB3191566-x64.zip

class Instance {
    [Backend] $Backend
    [String] $Name
    [String] $LogPath = "C:\temp\transcripts\launch_single_azure_vm_{0}.log"
    [String] $DefaultUsername
    [String] $DefaultPassword

    Instance ($Backend, $Name) {
        $transcriptPath = $this.LogPath -f @($Name)
        $transcriptPath = $transcriptPath + "-" + (get-date -Format s).replace(":","-")
        Start-Transcript -Path $transcriptPath -Force
        $this.Backend = $Backend
        $this.Name = $Name
        write-verbose ("Initialized instance wrapper for " + $this.Name)
    }

    [void] Cleanup () {
        $this.Backend.CleanupInstance($this.Name)
    }

    [void] CreateInstance () {
        $this.Backend.CreateInstance($this.Name)
    }

    [void] CreateFromSpecialized () {
        $this.Backend.CreateInstanceFromSpecialized($this.Name)
    }

    [void] CreateFromURN () {
        $this.Backend.CreateInstanceFromURN($this.Name, $this.useInitialPW)
    }

    [void] CreateFromGeneralized () {
        $this.Backend.CreateInstanceFromGeneralized($this.Name, $this.useInitialPW)
    }

    [void] StopInstance () {
        $this.Backend.StopInstance($this.Name)
    }

    [void] RemoveInstance () {
        $this.Backend.removeInstance($this.Name)
    }

    [String] GetPublicIP () {
        return $this.Backend.GetPublicIP($this.Name)
    }

    [object] GetVM () {
        return $this.Backend.GetVM($this.Name)
    }

    [String] SetupAzureRG() 
    {
        write-verbose "Setting up Azure RG"
        return $this.Backend.SetupAzureRG()
    }

    [string] WaitForAzureRG( ) {
        return $this.Backend.WaitForAzureRG( )
    }
}

class AzureInstance : Instance {
    AzureInstance ($Backend, $Name) : base ($Backend, $Name) {write-verbose "AzureInstance"}
}

class HypervInstance : Instance {
    [String] $VHDPath
    [String] $DvdDrive

    HypervInstance ($Backend, $Name) : base ($Backend, $Name) {
    }

    [void] CreateInstance () {
        $this.Backend.CreateInstance($this.Name, $this.VHDPath)
    }

    [void] AttachVMDvdDrive ($DvdDrive) {
        $this.Backend.AttachVMDvdDrive($this.Name, $DvdDrive)
    }
}


class Backend {
    [String] $Name="BaseBackend"

    Backend ($Params) {
        write-verbose ("Initialized backend " + $this.Name) 
    }

    [string] Serialize() {
        return $this | ConvertTo-Json
    }

    static [Backend] Deserialize([string] $Json) {
        $deserialized = ConvertFrom-Json -InputObject $Json
        $backend = [Backend]::new($deserialized.Name)
        return $backend
    }

    [Instance] GetInstanceWrapper ($InstanceName) {
        write-verbose ("Initializing instance on backend " + $this.Name)
        return $null
    }

    [void] CreateInstance ($InstanceName) {
    }

    [void] CreateInstanceFromSpecialized ($InstanceName) {
    }

    [void] CreateInstanceFromURN ($InstanceName, $useInitialPW) {
    }

    [void] CreateInstanceFromGeneralized ($InstanceName, $useInitialPW) {
    }

    [void] CleanupInstance ($InstanceName) {
        write-verbose ("Cleaning instance and associated resources on backend " + $this.Name) `
    }

    [void] RebootInstance ($InstanceName) {
        write-verbose ("Rebooting instance on backend " + $this.Name)
    }

    [String] GetPublicIP ($InstanceName) {
        write-verbose ("Getting instance public IP a on backend " + $this.Name)
        return $null
    }

    [object] GetVM($instanceName) {
       write-verbose ("Getting instance VM on backend " + $this.Name)
       return $null
    }

    [void] StopInstance($instanceName) {
       write-verbose ("StopInstance VM on backend " + $this.Name)
    }

    [void] RemoveInstance($instanceName) {
       write-verbose ("RemoveInstance VM on backend " + $this.Name)
    }

    [Object] GetPSSession ($InstanceName) {
        write-verbose ("Getting new Powershell Session on backend " + $this.Name)
        return $null
    }

    [string] SetupAzureRG( ) {
        write-verbose ("Setting up Azure Resource Groups " + $this.Name)
        return $null
    }

    [string] WaitForAzureRG( ) {
        write-verbose ("Waiting for Azure resource group setup " + $this.Name)
        return $null
    }
}

class AzureBackend : Backend {
    [String] $Name = "AzureBackend"
    [String] $SecretsPath = "C:\Framework-Scripts\secrets.ps1"
    [String] $CommonFunctionsPath = "C:\Framework-Scripts\common_functions.ps1"
    [String] $ProfilePath = "C:\Azure\ProfileContext.ctx"
    [String] $ResourceGroupName = "smoke_working_resource_group"
    [String] $StorageAccountName = "smokework"
    [String] $sourceImage = "sourceimage"
    [String] $ContainerName = "vhds-under-test"
    [String] $Location = "westus"
    [String] $VMFlavor = "Standard_D2_V2"
    [String] $NetworkName = "SmokeVNet"
    [String] $SubnetName = "SmokeSubnet"
    [String] $NetworkSecGroupName = "SmokeNSG"
    [String] $addressPrefix = "172.19.0.0/16"
    [String] $subnetPrefix = "172.19.0.0/24"
    [String] $blobURN = "Unset"
    [String] $blobURI = "Unset"
    [String] $suffix = "-Smoke-1"
    [String] $UseExistingResources = "yes"
    [String] $enableBootDiagnostics = "yes"
    [string] $useInitialPW = "yes"

    AzureBackend ($Params) : base ($Params) {
        Write-Verbose "Starting the backend"
        if (Test-Path $this.CommonFunctionsPath) {
            . $this.CommonFunctionsPath
        } else {
            Write-Verbose "Throwing for no common functions"
            throw "??? Common Functions file file does not exist."
        }
        write-Verbose "Backend CP 1"
        if (Test-Path $this.SecretsPath) {
            . $this.SecretsPath
        } else {
            Write-Verbose "Throwing for no secrets functions"
            throw "Secrets file does not exist."
        }
        write-Verbose "Backend CP 2"
    }

    [Instance] GetInstanceWrapper ($InstanceName) {
        if (Test-Path $this.CommonFunctionsPath) {
            . $this.CommonFunctionsPath
        } else {
            Write-Verbose "Throwing (2) for no secrets functions"
            throw "??? Common Functions file file does not exist."
        }

        if (Test-Path $this.SecretsPath) {
            . $this.SecretsPath
        } else {
            Write-Verbose "Throwing (2) for no secrets functions"
            throw "Secrets file does not exist."
        }
write-verbose  "Checkpoint 1"
        $this.suffix = $this.suffix -replace "_","-"
        login_azure $this.ResourceGroupName $this.StorageAccountName $this.Location
        write-verbose  "Checkpoint 2"
        $flavLow = $this.VMFlavor
        $flavLow = $flavLow.ToLower()
        $regionSuffix = ("---" + $this.Location + "-" + $flavLow) -replace " ","-"
        $regionSuffix = $regionSuffix -replace "_","-"
        write-verbose  "Checkpoint 3"
        $bar=$InstanceName.Replace("---","{")
        $imageName = $bar.split("{")[0]
        write-verbose  "Checkpoint 4"
        $imageName = $imageName + $regionSuffix
        $imageName = $imageName + $this.suffix
        $imageName = $imageName  -replace ".vhd", ""
        if ($imageName.Length -gt 62) {
            Write-Warning "NOTE:  Image name $imageName is too long"
            $imageName = $imageName.substring(0, 62)
            Write-Warning "NOTE:  Image name is now $imageName"
            if ($imageName.EndsWith("-") -eq $true) {                
                $imageName = $imageName -Replace ".$","X"
                Write-Warning "NOTE:  Image name is ended in an illegal character.  Image name is now $imageName"
            }
            Write-Warning "NOTE:  Image name $imageName was truncated to 62 characters"
        }
        write-verbose  "Checkpoint 5"
        $instance = [AzureInstance]::new($this, $imageName)
        if ($instance -eq $null) {
            write-Errpr "NULL INSTANCE"
        } else {
            write-verbose "All good"
        }
        
        return $instance
    }

    [string] SetupAzureRG( ) {
        #
        #  Avoid potential race conditions
        write-verbose "Getting the NSG"
        $sg = $this.getNSG()

        write-verbose "Getting the network"
        $VMVNETObject = $this.getNetwork($sg)

        write-verbose "Getting the subnet"
        $this.getSubnet($sg, $VMVNETObject)

        return "Success"
    }

    [string] WaitForAzureRG( ) {
        $azureIsReady = $false
        while ($azureIsReady -eq $false) {
            $sg = Get-AzureRmNetworkSecurityGroup -Name $this.NetworkSecGroupName -ResourceGroupName $this.ResourceGroupName
            if (!$sg) {
                Start-Sleep -Seconds 10
            } else {
                $VMVNETObject = Get-AzureRmVirtualNetwork -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName
                if (!$VMVNETObject) {
                    Start-Sleep -Seconds 10
                } else {
                    $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName -VirtualNetwork $VMVNETObject
                    if (!$VMSubnetObject) {
                        Start-Sleep -Seconds 10
                    } else {
                        $azureIsReady = $true
                    }
                }
            }
        }

        return "Success"
    }

    [void] StopInstance ($InstanceName) {
        write-verbose "Stopping machine $InstanceName"
        Stop-AzureRmVM -Name $InstanceName -ResourceGroupName $this.ResourceGroupName -Force
    }

    [void] RemoveInstance ($InstanceName) { 
        write-verbose "Removing machine $InstanceName"
        Remove-AzureRmVM -Name $InstanceName -ResourceGroupName $this.ResourceGroupName -Force
    }

    [void] CleanupInstance ($InstanceName) {
        $this.RemoveInstance($InstanceName)

        if ($this.UseExistingResources -eq "Yes") {
            write-verbose "Preserving existing PIP and NIC for future use."
        } else {
            write-verbose "Deleting NIC " $InstanceName
            $VNIC = Get-AzureRmNetworkInterface -Name $InstanceName -ResourceGroupName $this.ResourceGroupName 
            if ($VNIC -and $this.UseExistingResources -ne "Yes") {
                Remove-AzureRmNetworkInterface -Name $InstanceName -ResourceGroupName $this.ResourceGroupName -Force
            }

            write-verbose "Deleting PIP $InstanceName"
            $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $InstanceName
            if ($pip -and $this.UseExistingResources -ne "Yes") {
                Remove-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $InstanceName -Force
            }   
        }     
    }

    # Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup
    [object] getNSG()
    {
        $sg = Get-AzureRmNetworkSecurityGroup -Name $this.NetworkSecGroupName -ResourceGroupName $this.ResourceGroupName
        if (!$sg) {
            # write-verbose "Network security group does not exist for this region.  Creating now..." 
            $rule1 = New-AzureRmNetworkSecurityRuleConfig -Name "ssl-rule" -Description "Allow SSL over HTTP" `
                                                            -Access "Allow" -Protocol "Tcp" -Direction "Inbound" -Priority "100" `
                                                            -SourceAddressPrefix "Internet" -SourcePortRange "*" `
                                                            -DestinationAddressPrefix "*" -DestinationPortRange "443"
            $rule2 = New-AzureRmNetworkSecurityRuleConfig -Name "ssh-rule" -Description "Allow SSH" `
                                                            -Access "Allow" -Protocol "Tcp" -Direction "Inbound" -Priority "101" `
                                                            -SourceAddressPrefix "Internet" -SourcePortRange "*" -DestinationAddressPrefix "*" `
                                                            -DestinationPortRange "22"

            New-AzureRmNetworkSecurityGroup -Name $this.NetworkSecGroupName -ResourceGroupName $this.ResourceGroupName -Location $this.Location -SecurityRules $rule1,$rule2

            $sg = Get-AzureRmNetworkSecurityGroup -Name $this.NetworkSecGroupName -ResourceGroupName $this.ResourceGroupName
            # write-verbose "Done."
        }

        return $sg
    }

    # Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork
    [object] getNetwork($sg)
    {
        $VMVNETObject = Get-AzureRmVirtualNetwork -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName
        if (!$VMVNETObject) {
            # write-verbose "Network does not exist for this region.  Creating now..." 
            $VMSubnetObject = New-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName  -AddressPrefix $this.subnetPrefix -NetworkSecurityGroup $sg
            New-AzureRmVirtualNetwork   -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName -Location $this.Location -AddressPrefix $this.addressPrefix -Subnet $VMSubnetObject
            $VMVNETObject = Get-AzureRmVirtualNetwork -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName
        }

        return $VMVNETObject
    }

    # Microsoft.Azure.Commands.Network.Models.PSSubnet
    [object] getSubnet($sg,$VMVNETObject)
    {
        $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName -VirtualNetwork $VMVNETObject 
        if (!$VMSubnetObject) {
            # write-verbose "Subnet does not exist for this region.  Creating now..." 
            Add-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName -VirtualNetwork $VMVNETObject -AddressPrefix $this.subnetPrefix -NetworkSecurityGroup $sg
            Set-AzureRmVirtualNetwork -VirtualNetwork $VMVNETObject 
            $VMVNETObject = Get-AzureRmVirtualNetwork -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName
            $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName -VirtualNetwork $VMVNETObject 
        }

        return $VMSubnetObject
    }

    # Microsoft.Azure.Commands.Network.Models.PSPublicIpAddress
    [string] getPIP($pipName)
    {
        write-verbose "CALL TO GETPIP -- INCOMING PIPNAME IS $pipName"

        $pipName = $pipName.replace("_","-")
        $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $pipName 
        if (!$pip) {
            # write-verbose "Public IP does not exist for this region.  Creating now..." 
            New-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Location $this.Location `
                -Name $pipName -AllocationMethod Dynamic -IdleTimeoutInMinutes 4
            $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $pipName
        }

        return $pip.IpAddress
    }

    # Microsoft.Azure.Commands.Network.Models.PSNetworkInterface
    [object] getNIC([string] $nicName,
                    [object] $VMSubnetObject, 
                    [object] $pip)
    {
        Write-Verbose "GetNIC CP 1"
        $VNIC = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $this.ResourceGroupName 
        Write-Verbose "GetNIC CP 2"
        if (!$VNIC) {
            # write-verbose "Creating new network interface" 
            #
            #  Get the PIP
            $pip2 = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $nicName
            Write-Verbose "GetNIC CP 3"

            New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $this.ResourceGroupName `
                -Location $this.Location -SubnetId $VMSubnetObject.Id -publicipaddressid $pip2.Id

                Write-Verbose "GetNIC CP 4"
            $VNIC = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $this.ResourceGroupName
            Write-Verbose "GetNIC CP 5"
        }
        Write-Verbose "GetNIC CP 6"
        return $VNIC
    }

    [void] CreateInstanceFromSpecialized ($InstanceName) {        
        write-verbose "Creating a new VM config for $InstanceName..." 

        $sg = $this.getNSG()

        $VMVNETObject = $this.getNetwork($sg)

        $VMSubnetObject = $this.getSubnet($sg, $VMVNETObject)

        $vm = New-AzureRmVMConfig -VMName $InstanceName -VMSize $this.VMFlavor
        write-verbose "Assigning network $($this.NetworkName) and subnet config  $($this.SubnetName) with NSG  $($this.NetworkSecGroupName) to new machine" 

        write-verbose "Assigning the public IP address" 
        $ipName = $InstanceName
        write-verbose "------------------>>>>> -------------------->>>> 1111111 CAlling GETPIP with $ipName"
        $pip = $this.getPIP($ipName)

        write-verbose "Assigning the network interface" 
        $nicName = $InstanceName
        $VNIC = $this.getNIC($nicName, $VMSubnetObject, $pip)

        Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $this.ResourceGroupName 
        $VNIC.NetworkSecurityGroup = $sg
        
        Set-AzureRmNetworkInterface -NetworkInterface $VNIC

        write-verbose "Adding the network interface" 
        Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id
        
        #
        #  Code specific to a specialized blob
        $blobURIRaw = ("https://{0}.blob.core.windows.net/{1}/{2}.vhd" -f `
                       @($this.StorageAccountName, $this.ContainerName, $InstanceName))

        $vm = Set-AzureRmVMOSDisk -VM $vm -Name $InstanceName -VhdUri $blobURIRaw -CreateOption Attach -Linux

        if ($this.enableBootDiagnostics -ne "Yes") {
            write-verbose "Disabling boot diagnostics"
            Set-AzureRmVMBootDiagnostics -VM $vm -Disable
        }

        try {
            write-verbose "Starting the VM" 
            $NEWVM = New-AzureRmVM -ResourceGroupName $this.ResourceGroupName -Location $this.Location -VM $vm
            if (!$NEWVM) {
                Write-errpr "Failed to create VM"
            } else {
                Write-Verbose "VM $InstanceName started successfully..."
            }
        } catch {
            Write-Error "Caught exception attempting to start the new VM.  Aborting..."
            Stop-Transcript
            return
        }
    }

    [void] CreateInstanceFromURN ($InstanceName, $useInitialPW) {        
        write-verbose "Creating a new VM config for $InstanceName..." 

        $sg = $this.getNSG()

        $VMVNETObject = $this.getNetwork($sg)

        $VMSubnetObject = $this.getSubnet($sg, $VMVNETObject)

        $vm = New-AzureRmVMConfig -VMName $InstanceName -VMSize $this.VMFlavor
        write-verbose "Assigning network $($this.NetworkName) and subnet config $($this.SubnetName) with NSG $($this.NetworkSecGroupName) to new machine"

        write-verbose "Assigning the public IP address"
        
        $ipName = $InstanceName
        write-verbose "------------------>>>>> -------------------->>>> 2222222 CAlling GETPIP with $ipName"
        $pip = $this.getPIP($ipName)

        write-verbose "Assigning the network interface" 
        $nicName = $InstanceName
        $VNIC = $this.getNIC($nicName, $VMSubnetObject, $pip)
        $VNIC.NetworkSecurityGroup = $sg
        
        Set-AzureRmNetworkInterface -NetworkInterface $VNIC

        write-verbose "Adding the network interface"
        Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id

        write-verbose "Parsing the blob string $this.blobURN"
        $blobParts = $this.blobURN.split(":")
        $blobSA = $this.StorageAccountName
        $blobContainer = $this.ContainerName
        $osDiskVhdUri = "https://$blobSA.blob.core.windows.net/$blobContainer/"+$InstanceName+".vhd"

        $trying = $true
        $tries = 0
        while ($trying -eq $true) {
            $trying = $false
            
            write-verbose "Starting the VM" 
            if ($this.useInitialPW -eq "Yes") {
                $cred = make_cred_initial
            } else {
                $cred = make_cred
            }
            $vm = Set-AzureRmVMOperatingSystem -VM $vm -Linux -ComputerName $InstanceName -Credential $cred
            $vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName $blobParts[0] -Offer $blobParts[1] `
                -Skus $blobParts[2] -Version $blobParts[3]
            $vm = Set-AzureRmVMOSDisk -VM $vm -VhdUri $osDiskVhdUri -name $InstanceName -CreateOption fromImage -Caching ReadWrite

            if ($this.enableBootDiagnostics -ne "Yes") {
                write-verbose "Disabling boot diagnostics"
                Set-AzureRmVMBootDiagnostics -VM $vm -Disable
            }

            try {
                $NEWVM = New-AzureRmVM -ResourceGroupName $this.ResourceGroupName -Location $this.Location -VM $vm
                if (!$NEWVM) {
                    write-error "Failed to create VM $InstanceName"
                    Start-Sleep -Seconds 30
                    $trying = $true
                    $tries = $tries + 1
                    if ($tries -gt 5) {
                        break
                    }
                } else {
                    write-verbose "VM $InstanceName started successfully..." 
                }
            } catch {
                Write-error "Caught exception attempting to start the new VM.  Aborting..."
            }
        }
    }

    [void] CreateInstanceFromGeneralized ($InstanceName, $useInitialPW) {        
        write-verbose "Creating a new VM config..." 

        $sg = $this.getNSG()
        if ($? -eq $false -or $sg -eq $null) {
            Write-error "FAILED to get NSG"
        }

        $VMVNETObject = $this.getNetwork($sg)
        if ($? -eq $false -or $VMVNETObject -eq $null) {
            Write-Error "FAILED to get network"
        }

        $VMSubnetObject = $this.getSubnet($sg, $VMVNETObject)
        if ($? -eq $false -or $VMSubnetObject -eq $null) {
            Write-Error "FAILED to get getSubnet"
        }

        $vm = New-AzureRmVMConfig -VMName $InstanceName -VMSize $this.VMFlavor
        write-verbose "Assigning network $($this.NetworkName) and subnet config $($this.SubnetName) with NSG $($this.NetworkSecGroupName) to new machine" 

        write-verbose "Assigning the public IP address" 
        $ipName = $InstanceName
        write-verbose "------------------>>>>> -------------------->>>> 33333333 CAlling GETPIP with $ipName"
        $pip = $this.getPIP($ipName)

        write-verbose "Assigning the network interface" 
        $nicName = $InstanceName
        $VNIC = $this.getNIC($nicName, $VMSubnetObject, $pip)
        $VNIC.NetworkSecurityGroup = $sg
        
        Set-AzureRmNetworkInterface -NetworkInterface $VNIC

        write-verbose "Adding the network interface" 
        Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id

        #
        #  Create an image from the URI that we can then instantiate
        #$imageConfig = New-AzureRmImageConfig -Location $this.Location
        #$imageConfig = Set-AzureRmImageOsDisk -Image $imageConfig -OsState Generalized -BlobUri $this.blobURI -OsType Linux 

        #$image = New-AzureRmImage -ImageName $InstanceName -ResourceGroupName $this.ResourceGroupName -Image $imageConfig
        
        #
        #  Set up the OS disk
        # $blobURIRaw = $this.blobURI        
        # write-verbose "Setting up the OS disk.  Image name is $InstanceName, from URI $blobURIRaw"

        # $blobURIRaw = ("https://{0}.blob.core.windows.net/{1}/{2}.vhd" -f `
        #               @($this.StorageAccountName, $this.ContainerName, $InstanceName))

        $vhdURI = ("https://{0}.blob.core.windows.net/{1}/{2}.vhd" -f `
                            @($this.StorageAccountName, $this.ContainerName, $InstanceName))

        $blobSA = $this.StorageAccountName
        $blobContainer = $this.ContainerName
        #$osDiskVhdUri = "https://$blobSA.blob.core.windows.net/$blobContainer/"+$InstanceName+".vhd"
        $osDiskVhdUri = ("https://{0}.blob.core.windows.net/{1}/{2}.vhd" -f `
                            @($this.StorageAccountName, $this.ContainerName, $this.sourceImage)) 
        write-verbose "OSDIskVHD URI set to $osDiskVhdUri"
        

        if ($this.useInitialPW -eq "Yes") {
            $cred = make_cred_initial
        } else {
            $cred = make_cred
        }
        
        #$vm = Set-AzureRmVMSourceImage -VM $vm -Id $image.Id

        write-verbose "Setting up the OS disk"
        $vm = Set-AzureRmVMOSDisk -VM $vm -name $InstanceName -CreateOption fromImage  `
                                                -Caching ReadWrite -Linux -VhdUri $vhdURI -SourceImageUri $osDiskVhdUri
        write-verbose "Adding the operating system"
        $vm = Set-AzureRmVMOperatingSystem -VM $vm -Linux -ComputerName $InstanceName -Credential $cred
        # $vm = Set-AzureRmVMOSDisk -VM $vm -name $InstanceName -CreateOption fromImage -SourceImageUri $blobURIRaw `
        #                          -Caching ReadWrite -Linux
        # $vm = Set-AzureRmVMOSDisk -VM $vm -VhdUri $osDiskVhdUri -name $InstanceName -CreateOption fromImage -Caching ReadWrite
        
        if ($this.enableBootDiagnostics -ne "Yes") {
            write-verbose "Disabling boot diagnostics" 
            Set-AzureRmVMBootDiagnostics -VM $vm -Disable
        }
  
        try {
            write-verbose "Starting the VM" 
            $NEWVM = New-AzureRmVM -ResourceGroupName $this.ResourceGroupName -Location $this.Location -VM $vm
            if (!$NEWVM) {
                Write-error "Failed to create VM" 
            } else {
                write-verbose "VM $InstanceName started successfully..." 
            }
        } catch {
            Write-error "Caught exception attempting to start the new VM.  Aborting..."
            Stop-Transcript
            return
        }
    }

    [String] GetPublicIP ($InstanceName) {
        write-verbose "CALL TO GETPIP -- INCOMING PIPNAME IS $InstanceName"
        
        $pipName = $InstanceName.replace("_","-")
        $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $pipName 
        if (!$pip) {
            write-verbose "Public IP does not exist for this region.  Creating now..."
            New-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Location $this.Location `
                -Name $pipName -AllocationMethod Dynamic -IdleTimeoutInMinutes 4
            $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $pipName
        }

        return $pip.IpAddress
    }

    [Object] GetPSSession ($InstanceName) {
        return ([Backend]$this).GetPSSession()
    }

    [Object] GetVM($instanceName) {
        write-verbose "GetVM looking for $InstanceName"

        return Get-AzureRmVM -ResourceGroupName $this.ResourceGroupName -Name $InstanceName
    }
}


class HypervBackend : Backend {
    [String] $Name="HypervBackend"
    [String] $ComputerName
    [String] $SecretsPath
    [String] $UseExistingResources = $true
    [System.Management.Automation.PSCredential] $Credentials

    HypervBackend ($Params) : base ($Params) {
        $this.ComputerName = $Params[0]
        $this.SecretsPath = $Params[1]

        if ($this.SecretsPath -and (Test-Path $this.SecretsPath)) {
            $this.GetCredentials()
        } else {
            Write-warning "Credential file does not exist. Using current user context."
        }
    }

    [void] GetCredentials() {
        . $this.SecretsPath
        $securePassword = ConvertTo-SecureString -AsPlainText -Force $global:password
        $this.Credentials = New-Object System.Management.Automation.PSCredential `
            -ArgumentList $global:username, $securePassword
    }

    [string] RunHypervCommand ($params) {
        if ($this.Credentials) {
            $params += (@{"Credential"=$this.Credentials})
        }
        if ($this.ComputerName -and ($this.ComputerName -ne "localhost") `
                -and ($this.ComputerName -ne "127.0.0.1")) {
            $params += @{"ComputerName"=$this.ComputerName}
        }
        return (Invoke-Command @params)
    }

    [void] CreateInstance ($InstanceName, $VHDPath) {
        write-verbose ("Creating $InstanceName on backend " + $this.Name)
        $scriptBlock = {
            param($InstanceName, $VHDPath)

            New-VM -Name $InstanceName -VHDPath $VHDPath `
                   -MemoryStartupBytes 3500MB `
                   -Generation 1 `
                   -SwitchName "External"
            Set-VM -Name $InstanceName `
                   -ProcessorCount 2 `
                   -DynamicMemory:$false
            Set-VMMemory -VMName $InstanceName `
                         -DynamicMemoryEnabled $false
            Enable-VMIntegrationService -VMName $InstanceName `
                                        -Name "*"
            Start-VM -Name $InstanceName
            write-verbose "VM $InstanceName has been created and started."

        }
        $params = @{
            "ScriptBlock"=$scriptBlock;
            "ArgumentList"=@($InstanceName, $VHDPath);
        }
        $this.RunHypervCommand($params)
    }

    [Instance] GetInstanceWrapper ($InstanceName) {
        write-verbose ("Initializing $InstanceName on backend " + $this.Name)
        $instance = [HypervInstance]::new($this, $InstanceName)
        if (!$instance) {
            throw "Failed to initialize instance $InstanceName"
        }
        return $instance
    }

    [void] AttachVMDvdDrive ($InstanceName, $DvdDrive) {
        write-verbose ("Attaching DvdDrive to $InstanceName on backend " + $this.Name)
        $params = @{
            "ScriptBlock"={
                param($InstanceName, $DvdDrive)
                Set-VMDvdDrive -VM $InstanceName -Path $DvdDrive
            };
            "ArgumentList"=@($InstanceName, $DvdDrive);
        }
        $this.RunHypervCommand($params)
    }

    [void] StopInstance ($InstanceName) {
        write-verbose ("Stopping $InstanceName on backend " + $this.Name)
        $params = @{
            "ScriptBlock"={
                param($InstanceName)
                if (Get-VM -Name $InstanceName -ErrorAction SilentlyContinue) {
                    Stop-VM -Name $InstanceName -Force
                }
            };
            "ArgumentList"=@($InstanceName);
        }
        $this.RunHypervCommand($params)
    }

    [void] RemoveInstance ($InstanceName) {
        write-verbose ("Removing $InstanceName on backend " + $this.Name)
        $this.StopInstance($InstanceName)
        $params = @{
            "ScriptBlock"={
                param($InstanceName)
                if (Get-VM -Name $InstanceName -ErrorAction SilentlyContinue) {
                    Remove-VM -Name $InstanceName -Force
                }
            };
            "ArgumentList"=@($InstanceName);
        }
        $this.RunHypervCommand($params)
    }

    [void] RebootInstance ($InstanceName) {
        write-verbose ("Rebooting $InstanceName on backend " + $this.Name)
        $params = @{
            "ScriptBlock"={
                param($InstanceName)
                Restart-VM -Name $InstanceName -Force
            };
            "ArgumentList"=@($InstanceName);
        }
        $this.RunHypervCommand($params)
    }

    [string] Serialize() {
        return $this | ConvertTo-Json
    }

    static [HypervBackend] Deserialize([string] $Json) {
        $deserialized = ConvertFrom-Json -InputObject $Json
        $HypervBackend = [HypervBackend]::new(@($deserialized.ComputerName))
        return $HypervBackend
    }

    [void] CleanupInstance ($InstanceName) {
        write-verbose ("Cleaning $InstanceName on backend " + $this.Name) 
        $this.RemoveInstance($InstanceName)
        if ($this.UseExistingResources) {
            write-verbose "Preserving existing VHD for future use."
        } else {
            write-verbose "Removing VHD."
            $params = @{
                "ScriptBlock"={
                    param($VHDPath)
                    Remove-Item -Force $VHDPath
                };
                "ArgumentList"=@($this.VHDPath);
            }
            $this.RunHypervCommand($params)
        }
    }

    [String] GetPublicIP ($InstanceName) {
        # NOTE(papagalu):LIS drivers, LIS KVP daemon should be installed on the VM
        $scriptBlock = {
            param($InstanceName)
            (Get-VMNetworkAdapter -VMName $InstanceName).IPaddresses[0]
        }

        $params = @{
            "ScriptBlock"=$scriptBlock;
            "ArgumentList"=@($InstanceName);
        }
        $ip = ""
        do {
            Start-Sleep -s 10
            $ip = $this.RunHypervCommand($params)
        } while([string]::IsNullOrWhiteSpace($ip))

        return $ip
    }

    [object] GetVM ($InstanceName) {
        $params = @{
            "ScriptBlock"={
                param($InstanceName)
                Get-VM -Name $InstanceName
            };
            "ArgumentList"=@($InstanceName);
        }
        return ($this.RunHypervCommand($params))
    }

    [object] GetPSSession ($InstanceName) {
        if (!$this.Credentials) {
            return $null
        }
        $ip = $this.GetPublicIP($InstanceName)
        $session = New-PSSession -ComputerName $ip -Credential $this.Credentials
        return $session
    }
}


class BackendFactory {
    [Backend] GetBackend([String] $Type, $Params) {
        return (New-Object -TypeName $Type -ArgumentList $Params)
    }
}
