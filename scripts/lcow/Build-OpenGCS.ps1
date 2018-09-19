param (
    [parameter(Mandatory=$true)]
    [String] $BinariesPath,
    [String] $TestRepo,
    [String] $TestBranch,
    [String] $WorkDir,
    [String] $LogDestination
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$commonModulePath = Join-Path $scriptPath "CommonFunctions.psm1"
Import-Module $commonModulePath

function Get-Tests {
    param (
        [String] $TestRepo,
        [String] $TestBranch,
        [String] $WorkDir
    )

    $repoPath = Join-Path $WorkDir "opengcs"

    git clone -q -b $TestBranch $TestRepo $repoPath

    if (-not (Test-Path $repoPath)) {
        Write-Output "Error: cannot find tests folder. Wrong repo."
        exit 1
    } else {
        return $repoPath
    }
}

function Execute-Test {
    param (
        [String] $TestPath,
        [String] $LogDest
    )
    
    $scriptPath = Join-Path $TestPath "build.ps1"
    if (-not (Test-Path $scriptPath)) {
        Write-Output "Error: Cannot find the build script in folder: $TestPath"
    }
    
    try {
        & "${scriptPath}"
    } catch {
        throw $_
    }
}

function Main {
    if (-not $WorkDir) {
        $WorkDir = "lcow-stress"
    }
    if (Test-Path $WorkDir) {
        Remove-Item -Recurse -Force $WorkDir
    }
    if (Test-Path $LogDestination) {
        Remove-Item -Recurse -Force $LogDestination
    }
        
    New-Item -Type Directory -Path $WorkDir
    $WorkDir = Resolve-Path $WorkDir
    New-Item -Type Directory -Path $LogDestination
    $LogDestination = Resolve-Path $LogDestination

    $testPath = Get-Tests -TestRepo $TestRepo -TestBranch $TestBranch `
        -WorkDir $WorkDir

    Push-Location $testPath
    
    Prepare-Env -BinariesPath $BinariesPath `
        -TestPath $testPath
    Execute-Test -TestPath $testPath -LogDest $LogDestination
    
    Pop-Location
}

Main
