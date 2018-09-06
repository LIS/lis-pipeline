param (
    [String] $BinariesDestination,
    [String] $ArtifactsPath,
    [String] $ArtifactsDestination
)

$TEST_DEPENDENCIES = @{
    "dockerd.exe" = "https://master.dockerproject.org/windows/x86_64/dockerd.exe";
    "docker.exe" = "https://master.dockerproject.org/windows/x86_64/docker.exe";
    "docker-compose.exe" = "https://github.com/docker/compose/releases/download/1.21.0-rc1/docker-compose-Windows-x86_64.exe";
    "rtf.exe" = "https://69-89472225-gh.circle-artifacts.com/0/rtf-windows-amd64.exe"
}

$ErrorActionPreference = "Stop"

$scriptPath = Get-Location
$helpersPath = Join-Path $scriptPath "scripts\utils\powershell\helpers.psm1"
Import-Module $helpersPath

function Get-Kernel {
    param(
        [String] $ArtifactsPath,
        [String] $Destination
    )
    
    if (Test-Path $Destination) {
        Remove-Item -Recurse $Destination
    }
    New-Item -Type Directory -Path $Destination
    
    if (Test-Path "$ArtifactsPath\kernel") {
        Copy-Item "$ArtifactsPath\kernel" "$Destination"
    } elseif (Test-Path "$ArtifactsPath\lcow-kernel") {
        Copy-Item "$ArtifactsPath\lcow-kernel" "$Destination\kernel"
    } else {
        Write-Output "Error: Cannot find kernel in folder: $ArtifactsPath"
        exit 1
    }
    if (Test-Path "$ArtifactsPath\initrd.img") {
        Copy-Item "$ArtifactsPath\initrd.img" "$Destination"
    } elseif (Test-Path "$ArtifactsPath\lcow-initrd.img") {
        Copy-Item "$ArtifactsPath\lcow-initrd.img" "$Destination\initrd.img"
    } else {
        Write-Output "Error: Cannot find initrd.img in folder: $ArtifactsPath"
        exit 1
    }
}

function Get-TestDependencies {
    param (
        [hashtable] $Binaries,
        [String] $LocalDir,
        [String] $Destination
    )
    
    if (Test-Path $Destination) {
        Remove-Item -Recurse $Destination
    }
    New-Item -Type Directory -Path $Destination
    
    if ($LocalDir -and (Test-Path $LocalDir)) {
        foreach ($key in $Binaries.Keys) {
            if (Test-Path "${LocalDir}\${key}") {
                Copy-Item "${LocalDir}\${key}" "${Destination}\${key}"
                Write-Output "Binary file: ${key} found locally."
            } else {
                Download -From $Binaries[$key] -To "${Destination}\${key}"
                Write-Output "Binary file: ${key} downloaded from: $($Binaries[$key])"
            }
        }
    } else {
        foreach ($key in $Binaries.Keys) {
            Download -From $($Binaries[$key]) -To "${Destination}\${key}"
            Write-Output "Binary file: ${key} downloaded from: $($Binaries[$key])"
        }
    }
}

function Main {
    Get-Kernel -ArtifactsPath $ArtifactsPath -Destination $ArtifactsDestination
    Get-TestDependencies -Binaries $TEST_DEPENDENCIES -Destination $BinariesDestination
}

Main