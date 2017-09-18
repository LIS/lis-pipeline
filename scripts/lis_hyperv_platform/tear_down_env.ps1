param(
   [String] $InstanceName = "Instance1",
   [String] $ConfigDrivePath = "C:\path\to\configdrive\"
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPath = (get-item $scriptPath ).parent.FullName
. "$scriptPath\backend.ps1"

function Main {
    $backend = [HypervBackend]::new(@("localhost"))
    $instance = [HypervInstance]::new($backend, $InstanceName, $VHDPath)

    $instance.Cleanup()
    Remove-Item -Force "$InstanceName-id-rsa.pub"
    Remove-Item -Force "$InstanceName-id-rsa"
    Remove-Item -Force "$ConfigDrivePath.iso"
}

Main
