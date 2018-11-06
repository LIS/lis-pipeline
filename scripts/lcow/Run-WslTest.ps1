param (
    [parameter(Mandatory=$true)]
    [String] $ArchivePath,
    [String] $BinariesPath,
    [String] $WorkDir,
    [String] $LogDestination
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$commonModulePath = Join-Path $scriptPath "CommonFunctions.psm1"
Import-Module $commonModulePath

$REMOTE_SCRIPT = ".\scripts\lcow\remote_scripts\run_wsl_tests.sh"
$TESTS_FOLDER = "testscripts"
$TEST_CONTAINER = "ubuntu"

function Get-Deps {
    param (
        [String] $ArchivePath,
        [String] $RemoteScript
    )
    
    if (-not (Test-Path $ArchivePath)) {
        throw "Cannot find script archive" 
    }
    
    Copy-Item $ArchivePath .
    $ArchiveName = $ArchivePath.Split("\")[-1]
    Expand-Archive $ArchiveName
    if (-not (Test-Path $TESTS_FOLDER)) {
        throw "Cannot find expanded wsl folder"
    }
    
    Copy-Item $RemoteScript .
}

function Execute-Test {
    param (
        [String] $LogDestination,
        [String] $WorkDir
    )
    
    $remoteScriptName = $REMOTE_SCRIPT.Split("\")[-1]
    
    try {
        docker run --rm --platform linux -v "${WorkDir}:/tests" `
            $TEST_CONTAINER bash -xec "apt update && apt install -y dos2unix && dos2unix /tests/$remoteScriptName && bash /tests/$remoteScriptName --tests_dir /tests/$TESTS_FOLDER --log_dir /tests/logs"
    } catch {
        throw $_
    } finally {
        $logPath = Join-Path $WorkDir "logs"
        Copy-Item "$logPath\*" $LogDestination
    }
}

function Main {
    if (-not $WorkDir) {
        $WorkDir = "docker-wsl"
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
    $RemoteScript = Resolve-Path $REMOTE_SCRIPT

    Push-Location $WorkDir
    
    Prepare-Env -BinariesPath $BinariesPath `
        -TestPath $WorkDir
    Get-Deps -ArchivePath $ArchivePath -RemoteScript $RemoteScript
        
    Execute-Test -WorkDir $WorkDir -LogDestination $LogDestination
    
    Pop-Location
}

Main