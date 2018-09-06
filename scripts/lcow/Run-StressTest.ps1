param (
    [parameter(Mandatory=$true)]
    [String] $BinariesPath,
    [String] $TestRepo,
    [String] $TestBranch,
    [String] $WorkDir,
    [String] $LogDestination
)

$TEST_CONTAINER_NAME = "stress-test"
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
    
    $repoPath = Join-Path $WorkDir "docker-stress"
    git clone -b $TestBranch $TestRepo $repoPath
    
    $dockerFilePath = Join-Path $repoPath "Dockerfile"
    if (-not (Test-Path $dockerFilePath)) {
        Write-Output "Error: cannot find Dockerfile. Wrong repo."
        exit 1
    } else {
        Push-Location $repoPath
    }
    
    docker build -t $ContainerName .
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Error: docker build failed."
        exit 1
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
        docker run --rm --platform linux $ContainerName --cpu 2 --io 1 --vm 2 --vm-bytes 128M --timeout 10s
    } catch {
        throw $_
    }
}

function Main {
    if (-not $WorkDir) {
        $WorkDir = "lcow-stress"
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
