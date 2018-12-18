param (
    [parameter(Mandatory=$true)]
    [String] $BinariesPath,
    [String] $TestRepo,
    [String] $WorkDir,
    [String] $LogDestination,
    [String] $BaseNumber
)

$TEST_CONTAINER_NAME = "docker_test"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$commonModulePath = Join-Path $scriptPath "CommonFunctions.psm1"
Import-Module $commonModulePath

function Execute-Test {
    param (
        [String] $TestPath
    )

    try {
       ./setup.ps1 
    } catch {
        throw $_
    }
    
    .\Run-DockerLinuxPullAutomation.ps1 -RootDir $TestPath -ConfigFile $TestPath\LinuxAppPullImageList.xml -ImageName linux -NetworkName nat -UseNat $true -Xenon $true -UseDataVolume $true -VolumeName $TestPath\volume -DataVolumeType Local -Verbose:$false
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
        
    New-Item -Type Directory -Path $WorkDir\docker_test
    $WorkDir = Resolve-Path $WorkDir
    New-Item -Type Directory -Path $LogDestination
    $LogDestination = Resolve-Path $LogDestination

	$repoPath = Join-Path $WorkDir "docker_test\hypervtest.zip" 
    
    Write-Host $repoPath 
    
    wget $TestRepo -outfile $repoPath     
	Expand-Archive $repoPath -DestinationPath $WorkDir
	$WorkDir= Join-Path $WorkDir "hypervlcowtest"
    Push-Location $WorkDir
    
    Prepare-Env -BinariesPath $BinariesPath `
        -TestPath $WorkDir
        
    Execute-Test -TestPath $WorkDir 
    Copy-Item $WorkDir\log*\* -Destination $LogDestination -Recurse

    Pop-Location

    $summaryPath = Join-Path $LogDestination "AppSummary.csv"
    if (Test-Path $summaryPath) {
        $summaryContent = Get-Content $summaryPath -Raw
    } else {
        throw "Cannot find summary file: AppSummary.csv"
    }

    $failureNumber = 0

    $testResults = $($summaryContent -split "`r`n`r`n")
    foreach ($result in $testResults) {
        if ($result -eq "" ) {
            continue
        }
        $result =  $result.Split("`n")
        if ($result[12].Split(":")[1].Trim() -ne "0") {
            $failureNumber ++
        }
    }
    if ($failureNumber -ge $BaseNumber) {
        Write-Host "Tests fail more that expected $BaseNumber number of failures, total number of failures for this run was $failureNumber"
        exit 1
    } else {
        exit 0
    }
}

Main

