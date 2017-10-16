param(
    [String] $InstanceName = "Instance1"
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptPath\asserts.ps1"

$scriptPath1 = (get-item $scriptPath ).parent.FullName
. "$scriptPath1\backend.ps1"

function Main {
    $backend = [HypervBackend]::new(@("localhost"))
    $instance = [HypervInstance]::new($backend, $InstanceName, $VHDPath)

    $vhdPaths = $instance.GetVMDisk()
    $vhdPaths = $vhdPaths.Split(" ")
    foreach ($path in $vhdPaths) {
        Write-Host $path
        if ($path -like "*ubuntu-cloud.vhdx") {
            $vhdPath = $path
            break
        }
    }

    $instance.Cleanup()

    $deployPath = Split-Path $vhdPath
    $jobPath = Split-Path $deployPath

    Assert-PathExists $jobPath

    Remove-Item -Force -Recurse $jobPath
}

Main
