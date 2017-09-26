param(
    [String] $JobPath = "C:\var\lib\lava\tmp\1",
    [String] $InstanceName = "Instance1"
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPath1 = (get-item $scriptPath ).parent.FullName
. "$scriptPath1\backend.ps1"

function Main {
    $backend = [HypervBackend]::new(@("localhost"))
    $instance = [HypervInstance]::new($backend, $InstanceName, $VHDPath)

    $instance.Cleanup()
    Remove-Item -Force "$JobPath\$InstanceName-id-rsa.pub"
    Remove-Item -Force "$JobPath\$InstanceName-id-rsa"
    Remove-Item -Force "$JobPath\configdrive.iso"
}

Main
