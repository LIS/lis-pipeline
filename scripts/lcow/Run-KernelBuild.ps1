param (
    [parameter(Mandatory=$true)]
    [String] $BinariesPath,
    [String] $TestRepo,
    [String] $TestBranch,
    [String] $WorkDir,
    [String] $LogDestination
)

$TEST_CONTAINER_NAME = "kernel_builder"
$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$commonModulePath = Join-Path $scriptPath "CommonFunctions.psm1"
Import-Module $commonModulePath

function Get-Container {
    param (
        [String] $TestRepo,
        [String] $TestBranch,
        [String] $ContainerName,
        [String] $WorkDir
    )
    
    $repoPath = Join-Path $WorkDir "kernel_builder"
    git clone -b $TestBranch $TestRepo $repoPath
    
    $dockerFilePath = Join-Path $repoPath "Dockerfile"
    if (-not (Test-Path $dockerFilePath)) {
        Write-Output "Error: cannot find Dockerfile. Wrong repo."
        exit 1
    } else {
        Push-Location $repoPath
    }
    
    Pop-Location 
}

function Execute-Test {
    param (
        [String] $TestPath,
        [String] $ContainerName,
        [String] $LogDest
    )

    try {
        docker run --rm --platform linux  moul/kernel-builder /bin/bash -xec 'git checkout v4.3 && cores=$(cat /proc/cpuinfo | grep --count processor) && threads=$(expr $cores*2 | bc) && make oldconfig && make -j $threads'
    } catch {
        throw $_
    }
}

function Main {
    if (-not $WorkDir) {
        $WorkDir = "lcow-kernel-build"
    }
    if (Test-Path $WorkDir) {
        Remove-Item -Recurse $WorkDir
    }
    if (Test-Path $LogDestination) {
        Remove-Item -Recurse $LogDestination
    }
        
    New-Item -Type Directory -Path $WorkDir
    $WorkDir = Resolve-Path $WorkDir
    New-Item -Type Directory -Path $LogDestination
    $LogDestination = Resolve-Path $LogDestination

    Push-Location $WorkDir
    
    Prepare-Env -BinariesPath $BinariesPath `
        -TestPath $WorkDir
    Get-Container -TestRepo $TestRepo -TestBranch $TestBranch `
        -WorkDir $WorkDir -ContainerName $TEST_CONTAINER_NAME
        
    Execute-Test -TestPath $WorkDir -ContainerName $TEST_CONTAINER_NAME `
        -LogDest $LogDestination
    
    Pop-Location
}

Main
