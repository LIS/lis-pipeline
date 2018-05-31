param(
    [parameter(Mandatory=$true)]
    [String] $JobId,
    [parameter(Mandatory=$true)]
    [String] $InstanceName,
    [parameter(Mandatory=$true)]
    [String] $VHDType,
    [parameter(Mandatory=$true)]
    [String] $XmlTest,
    [Int]    $VMCheckTimeout = 500,
    [String] $WorkingDirectory = ".",
    [String] $OsVersion,
    [String] $LISAImagesShareUrl,
    [String] $LisaTestDependencies,
    [String] $LocalKernelFolder
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPathParent = (Get-Item $scriptPath ).Parent.FullName

. "$scriptPath\XMLParser.ps1"

$LISA_TEST_RESULTS_REL_PATH = ".\TestResults\*\ica.log"

Import-Module "$scriptPathParent\utils\powershell\helpers.psm1"
Import-Module "$scriptPathParent\utils\powershell\ini.psm1"


function Get-LisaCode {
    param(
        [parameter(Mandatory=$true)]
        [string] $LISAPath
    )
    if (Test-Path $LISAPath) {
        rm -Recurse -Force $LISAPath
    }
    git clone https://github.com/LIS/lis-test.git $LISAPath
}

function Copy-LisaTestDependencies {
    param(
        [parameter(Mandatory=$true)]
        [string[]] $TestDependenciesFolders,
        [parameter(Mandatory=$true)]
        [string] $LISARelPath
    )

    # This function copies test dependencies in lisa folder
    # from a given share
    if (!(Test-Path $LisaTestDependencies)) {
        throw "$LisaTestDependencies path does not exist!"
    }
    foreach ($folder in $TestDependenciesFolders) {
        $LisaDepPath = Join-Path $LisaTestDependencies $folder
        Copy-Item -Force `
            -Recurse -Path $LisaDepPath `
            -Destination $LISARelPath
    } 
}

function Edit-XML{
    param(
        [String] $Path,
        [String] $VMSuffix
    )

    $parser = [XMLParser]::new($Path)
    $parser.InsertInstallKernel()
    $parser.ChangeVM($VMSuffix)
    $parser.Save($Path)
}

function Copy-TestResults {
    param (
        [String] $LogsPath,
        [String] $LISAPath
    )

    $LISAParentPath = (Get-Item $LISAPath).Parent.Name
    $logsFullPath = Join-Path $LogsPath $LISAParentPath
    New-Item -ItemType Directory -Path $logsFullPath -Force
    $LISALogPath = Join-Path $LISAPath "WS2012R2\lisa\TestResults\*"
    Copy-Item -Recurse -Force $LISALogPath $logsFullPath
}

function Main {

    if (!(Test-Path $WorkingDirectory)) {
        New-Item -ItemType "Directory" -Path $WorkingDirectory
    }
    $jobPath = Join-Path -Path (Resolve-Path $WorkingDirectory) -ChildPath $JobId
    New-Item -Path $jobPath -Type "Directory" -Force
    $LISAPath = Join-Path $jobPath "lis-test"
    $LISARelPath = Join-Path $LISAPath "WS2012R2\lisa"

    Write-Host "Getting the proper VHD folder name for LISA with ${OsVersion} and ${VHDType}"
    $imageFolder = Join-Path $LISAImagesShareUrl ("{0}\{0}_{1}" -f @($VHDType, $OsVersion))
    Write-Host "Getting LISA code..."
    Get-LisaCode -LISAPath $LISAPath

    Write-Host "Copying lisa dependencies from share"
    Write-Host "LISARelPath is " + $LISARelPath
    Write-Host $LisaTestDependencies
    Copy-LisaTestDependencies `
        -TestDependenciesFolders @("bin", "Infrastructure", "tools", "ssh") `
        -LISARelPath $LISARelPath

    Write-Host "Starting to edit XML file"
    
    if ([System.IO.Path]::IsPathRooted($XmlTest)) {
        $xmlPath = "$LISARelPath\xml\CustomXml.xml"
        Copy-Item -Path $XmlTest -Destination $xmlPath
        $XmlTest = "CustomXml.xml"
    } else {
        $xmlPath = "$LISARelPath\xml\$XmlTest"
    }
    Write-Host "xml path is " + $xmlPath
    Edit-XML $xmlPath $InstanceName
    Write-Host "finished to edit XML file"

    Write-Host "Started running LISA"
    if (!(Test-Path $LocalKernelFolder)) {
        throw "Kernel folder does not exist"
    } else {
        $LocalKernelFolder = Resolve-Path $LocalKernelFolder
    }
    Push-Location $LISARelPath
    try {
        $lisaParams = ("distro={0};localPath={1}" `
            -f @($VHDType, $LocalKernelFolder))
        # Note(avladu): Lisa requires ErrorActionPreference = Continue,
        # otherwise it will fail to run all the tests.
        $ErrorActionPreference = "Continue"
        $commandParams = @{"cmdVerb" = "run";"cmdNoun" = ".\xml\$XmlTest"; `
            "dbgLevel" = "6";"CLImageStorDir" = $imageFolder;"testParams" = $lisaParams}
        & .\lisa.ps1 @commandParams
        if ($LASTEXITCODE) {
            throw "Failed running LISA with exit code: ${LASTEXITCODE}"
        } else {
            Write-Host "Finished running LISA with exit code: ${LASTEXITCODE}"
        }
    } catch {
        throw $_
    } finally {
        $parentProcessPid = $PID
        $children = Get-WmiObject WIN32_Process | where `
            {$_.ParentProcessId -eq $parentProcessPid `
             -and $_.Name -ne "conhost.exe"}
        foreach ($child in $children) {
            Stop-Process -Force $child.Handle -Confirm:$false `
                -ErrorAction SilentlyContinue
        }

        Pop-Location
        New-Item -Type "Directory" -Force $JobId
        Copy-Item -Recurse -Force (Join-Path $jobPath "lis-test\WS2012R2\lisa\TestResults") $JobId
    }
}

Main
