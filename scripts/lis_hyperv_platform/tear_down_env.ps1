param(
    [String] $InstanceName = "Instance1"
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

$scriptPath1 = (get-item $scriptPath ).parent.FullName
. "$scriptPath1\backend.ps1"
. "$scriptPath1\common_functions.ps1"


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
