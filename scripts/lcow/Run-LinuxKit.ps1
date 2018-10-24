param (
    [parameter(Mandatory=$true)]
    [String] $BinariesPath,
    [String] $TestRepo,
    [String] $TestBranch,
    [String] $WorkDir,
    [String] $BaseNumber,
    [String] $LogDestination
)

$SUMMARY_JSON_REL_PATH = "_results\latest\SUMMARY.json"

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

function Compare-Results {
    param (
        [String] $TestPath,
        [String] $BaseNumber
    )

    $summaryFile = Join-Path $TestPath $SUMMARY_JSON_REL_PATH

    if (-not (Test-Path $summaryFile)) {
        throw "Cannot find test summary"
    }

    $summary = Get-Content $summaryFile | ConvertFrom-Json
    $passedTests = $($summary.results | where {$_.result -eq 0}).Length
    
    return ($passedTests - $BaseNumber)
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
    
    $result = Compare-Results -TestPath $testRepoPath `
        -BaseNumber $BaseNumber

    Pop-Location

    if ($result -ge 0) {
        Write-Output "Passed tests over base kernel: $result"
        exit 0
    } else {
        Write-Output "Failed tests over base kernel: $(0 - $result)"
        exit 1
    }
}

Main