param (
    [String] $JobPath = "C:\path\to\job",
    [String] $VHDPath = "C:\path\to\example.vhdx",
    [String] $UserdataPath = "C:\path\to\userdata.sh",
    [String[]] $KernelURL = @(
        "http://URL/TO/linux-headers.deb",
        "http://URL/TO/linux-image.deb",
        "http://URL/TO/hyperv-daemons.deb"),
    [String] $InstanceName = "Instance1",
    [String] $MkIsoFS = "C:\path\to\mkisofs.exe",
    [String] $LavaToolsDisk = "C:\path\to\tools"
)


$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

$scriptPath1 = (get-item $scriptPath).parent.FullName
. "$scriptPath1\backend.ps1"
. "$scriptPath1\common_functions.ps1"

function Main {
    Assert-PathExists $JobPath
    
    $backend = [HypervBackend]::new(@("localhost"))
    $instance = [HypervInstance]::new($backend, $InstanceName, $VHDPath)

    Write-Host "Starting Setup-Metadata script."
    & "$scriptPath/setup_metadata.ps1" $JobPath $UserdataPath $KernelURL $MkIsoFS
    if ($LastExitCode -ne 0) {
        throw $Error[0]
    }

    $instance.CreateInstance()
    $instance.AttachVMDvdDrive("$JobPath/configdrive.iso")
    $instance.AddVMDisk($LavaToolsDisk)
    $instance.StartInstance()
}

Main
