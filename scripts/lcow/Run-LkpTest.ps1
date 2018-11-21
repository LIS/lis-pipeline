param (
    [String] $BinariesPath,
    [String] $WorkDir,
    [String] $LogDestination
)

$REMOTE_SCRIPT = ".\scripts\lcow\remote_scripts\run_lkp_tests.sh"
$TEST_CONTAINER = "ubuntu"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$commonModulePath = Join-Path $scriptPath "CommonFunctions.psm1"
Import-Module $commonModulePath

function Execute-Test {
    param (
        [String] $LogDestination,
        [String] $WorkDir
    )
    
    $remoteScriptName = $REMOTE_SCRIPT.Split("\")[-1]
    
    try {
        docker run --rm --platform linux -v "${WorkDir}:/tests" `
            $TEST_CONTAINER bash -xec "apt update && apt install -y dos2unix && dos2unix /tests/$remoteScriptName && bash /tests/$remoteScriptName --work_dir /tests/lkp-workdir --log_dir /tests/logs"
    } catch {
        throw $_
    } finally {
        $logPath = Join-Path $WorkDir "logs"
        Copy-Item -Recurse "$logPath\*" $LogDestination
    }
}

function Main {
    if (-not $WorkDir) {
        $WorkDir = "docker-lkp"
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
    $BinariesPath = Resolve-Path $BinariesPath

    Push-Location $WorkDir
    
    Prepare-Env -BinariesPath $BinariesPath `
        -TestPath $WorkDir
    Copy-Item $RemoteScript .
        
    Execute-Test -WorkDir $WorkDir -LogDestination $LogDestination
    
    Pop-Location
}

Main