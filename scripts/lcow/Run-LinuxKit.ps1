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
    
    $repoPath = Join-Path $WorkDir "linuxkit"
    git clone -q -b $TestBranch $TestRepo $repoPath
    
    $testsDir = Join-Path $repoPath "tests"
    if (-not (Test-Path $testsDir)) {
        Write-Output "Error: cannot find tests folder. Wrong repo."
        exit 1
    } else {
        return $testsDir
    }
}

function Copy-Logs {
    param (
        [String] $TestPath,
        [String] $LogDest
    )
    
    $testLogs = Join-Path $TestPath "_results\latest"
    Copy-Item "${testLogs}\*" $LogDest
}

function Execute-Tests {
    param (
        [String] $TestPath,
        [String] $LogDest
    )
    
    try {
        rtf.exe run
    } catch {
        throw $_
    } finally {
        Copy-Logs -TestPath $TestPath -LogDest $LogDest
        exit 0
    }
}

function  Main {
    if (-not $WorkDir) {
        $WorkDir = "lcow-testing"
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
    
    $testRepoPath = Get-Tests -TestRepo $TestRepo -TestBranch $TestBranch `
        -WorkDir $WorkDir

    Push-Location $testRepoPath
    
    Prepare-Env -BinariesPath $BinariesPath `
        -TestPath $testRepoPath
    Execute-Tests -TestPath $testRepoPath -LogDest $LogDestination
    
    Pop-Location
}

Main