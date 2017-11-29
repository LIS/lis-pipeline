param (
    [Parameter(Mandatory=$false)] [switch] $startMachines,
    [Parameter(Mandatory=$false)] [switch] $stopMachines
)

set-location c:\Framework-Scripts
. c:\Framework-Scripts\common_functions.ps1
. c:\Framework-Scripts\secrets.ps1

#
#  First start the machines
$flavs = "Standard_D1_v2,Standard_D3_v2,Standard_D4_v2"
$Names = "OpenLogic-CentOS-73-LAT,Ubuntu1604-LTS-LATEST"
$SSA ="smokebvtstorageaccount"
$SRG="smoke_bvts_resource_group"
$SContainer="vhds"

$DSA="variantsdemo2"
$DRG="variants_test_demo_2"
$DContainer="running-variants"

$oldSuffix="-generalized.vhd"
$Suffix = "-Variant.vhd"

$nw="SmokeVNet"
$nsg="SmokeNSG"
$sn="SmokeSubnet-1"
$loc="westus"

$overallTimer = [Diagnostics.Stopwatch]::StartNew()
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

write-host "***************************************************************************************************"
write-host "*              HIPPEE Variants Demonstration -- Two Distros and Three Flavors                     *"
write-host "***************************************************************************************************"

if ($startMachines -eq $true) {
    #
    #  Step 1:  Instantiate the variants
    write-host "Starting the variant machines..." 
    .\start_variants.ps1  -sourceRG $SRG -sourceSA $SSA -sourceContainer $SContainer  `
                                -destRG   $DRG   -destSA   $DSA   -destContainer $DContainer `
                                -Flavors  $flavs  -requestedNames $Names -currentSuffix $oldSuffix `
                                -newSuffix $Suffix -network $nw -subnet $sn -NSG $nsg `
                                -location $loc -Verbose
    write-host "Machines are up" 
}

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed to start the variant group" -ForegroundColor Magenta
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

#
#  Now get a list of the running VMs
write-host "Executing a command against the launched machines..."
$variantNamesMessedUp = .\create_variant_name_list.ps1 -Flavors $flavs -requestedNames $names -location $loc -suffix $suffix -Verbose
foreach ($baseName in $variantNamesMessedUp)
{
    if ($baseName -ne "")
    {
        $variantNames = $variantNames + $baseName + ","
    }
}
$variantNames = $variantNames -Replace ".$",""

#
#  Run a command across the group
.\run_command_on_machines_in_group.ps1 -requestedNames $variantNames -destSA $DSA -destRG $DRG -suffix "" -command "lscpu" -location $loc -Verbose
write-host "Command execution complete."

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed run the command aginst all machines" -ForegroundColor Magenta
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

#
#  If desired, shut down the topology
if ($stopMachines -eq $true) {
    write-host "Deallocating the launched machines..."
    deallocate_machines_in_list $variantNames $destRG $destSA $location
    write-host "Deallocating the launched machines..."
}

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed to deallocate the remove the NIC and PIP for the variant group" -ForegroundColor Magenta
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

$overallTimer.Stop()
$elapsed = $overallTimer.Elapsed
Write-Host "It required $elapsed to instantiate the topology, run the command, and take the topology down." -ForegroundColor Magenta
write-host "***************************************************************************************************"
write-host "*              HIPPEE Variants Demonstration Complete!  Thanks for playing!                       *"
write-host "***************************************************************************************************"