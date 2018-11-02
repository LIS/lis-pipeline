param (
    [parameter(Mandatory=$true)]
    [String] $BinariesPath,
    [String] $TestRepo,
    [String] $WorkDir,
    [String] $LogDestination
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
	try {
		.\Run-DockerLinuxPullAutomation.ps1 -RootDir $TestPath -ConfigFile $TestPath\LinuxAppPullImageList.xml -ImageName linux -NetworkName nat -UseNat $true -Xenon $true -UseDataVolume $true -VolumeName $TestPath\volume -DataVolumeType Local -Verbose:$false
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
}

Main

