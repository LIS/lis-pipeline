param (
    [parameter(Mandatory=$true)]
    [String] $KernelUrl,
    [parameter(Mandatory=$true)]
    [String] $InitrdUrl,
    [parameter(Mandatory=$true)]
    [String] $Destination
)

$ErrorActionPreference = "Stop"

$scriptPath = Get-Location
$helpersPath = Join-Path $scriptPath "scripts\utils\powershell\helpers.psm1"
Import-Module $helpersPath

function Main {

    if (Test-Path $Destination) {
        Remove-Item -Recurse $Destination
    }
    New-Item -Type Directory -Path $Destination
    
    $kernelDest = Join-Path $Destination "kernel"
    $initrdDest = Join-Path $Destination "initrd.img"
    
    Download -From $KernelUrl -To $kernelDest
    Download -From $InitrdUrl -To $initrdDest
}

Main