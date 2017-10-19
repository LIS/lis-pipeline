param(
    [String] $InstanceName = "Instance1"
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

$scriptPath1 = (get-item $scriptPath ).parent.FullName
. "$scriptPath1\backend.ps1"
. "$scriptPath1\common_functions.ps1"

function Main {
    $backend = [HypervBackend]::new(@("localhost"))
    $instance = [HypervInstance]::new($backend, $InstanceName, $VHDPath)

    $vhdPath = $instance.GetVMDisk()
    if (!$vhdPath) {
        Write-Host "Instance $InstanceName doesn't exist."
        exit 0
    }

    $instance.Cleanup()

    $deployPath = Split-Path $vhdPath
    $jobPath = Split-Path $deployPath

    Assert-PathExists $jobPath

    Remove-Item -Force -Recurse $jobPath
}

Main
