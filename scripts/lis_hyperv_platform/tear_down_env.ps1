param(
    [String] $InstanceName = "Instance1"
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPathParent = (Get-Item $scriptPath ).Parent.FullName
Import-Module "$scriptPathParent\utils\powershell\helpers.psm1"
. "$scriptPathParent\utils\powershell\backend.ps1"

$WORKING_DIRECTORY = "C:\workspace"

function Main {
    $backend = [HypervBackend]::new(@("localhost"))
    $instance = [HypervInstance]::new($backend, $InstanceName, $VHDPath)

    $instance.Cleanup()

    $jobPath = "$WORKING_DIRECTORY\$InstanceName"
    Assert-PathExists $jobPath

    Remove-Item -Force -Recurse $jobPath
}

Main
