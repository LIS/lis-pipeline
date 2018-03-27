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
    [String] $QemuPath = "C:\bin\qemu-img.exe",
    [String] $UbuntuImageURL = "https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img",
    [String] $CentosImageURL = "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2",
    [String] $KernelVersionPath = "scripts\package_building\kernel_versions.ini",
    [switch] $LISAManageVMS,
    [String] $OsVersion,
    [String] $LISAImagesShareUrl,
    [String] $AzureToken,
    [String] $AzureUrl,
    [String] $SharedStoragePath,
    [String] $ShareUser,
    [String] $SharePassword,
    [String] $IdRSAPub,
    [String] $LisaTestDependencies,
    [String] $PipelineName,
    [String] $DBConfigPath,
    [String] $LisaTestSuite
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPathParent = (Get-Item $scriptPath ).Parent.FullName

$LISA_TEST_RESULTS_REL_PATH = ".\TestResults\*\ica.log"

Import-Module "$scriptPathParent\utils\powershell\ini.psm1"
Import-Module "$scriptPathParent\utils\powershell\helpers.psm1"


function Main {
    $KernelVersionPath = Join-Path $env:Workspace $KernelVersionPath
    $kernelFolder = Get-IniFileValue -Path $KernelVersionPath `
        -Section "KERNEL_BUILT" -Key "folder"
    if (!$kernelFolder) {
        throw "Kernel folder cannot be empty."
    }
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
    Copy-LisaTestDependencies `
        -TestDependenciesFolders @("bin", "Infrastructure", "tools", "ssh") `
        -LISARelPath $LISARelPath -LisaTestDependencies $LisaTestDependencies

    Push-Location "${LISARelPath}\xml"
    try {
        Edit-TestXML -Path $XmlTest -VMSuffix $InstanceName
        if ($LisaTestSuite) {
            Remove-XmlVMs -Path $XmlTest -Suite $LisaTestSuite
        }
    } catch {
        throw
    } finally {
        Pop-Location
    }

    Push-Location $LISARelPath
    Write-Host "Started running LISA"
    try {
        $lisaParams = ("SHARE_URL='{0}';AZURE_TOKEN='{1}';KERNEL_FOLDER='{2}'" `
            -f @($AzureUrl, $AzureToken, $kernelFolder))
        # Note(avladu): Lisa requires ErrorActionPreference = Continue,
        # otherwise it will fail to run all the tests.
        $ErrorActionPreference = "Continue"
        $commandParams = @{"cmdVerb" = "run";"cmdNoun" = ".\xml\${XmlTest}"; `
            "dbgLevel" = "6";"CLImageStorDir" = $imageFolder;"testParams" = $lisaParams}
        if ($LisaTestSuite) {
            $commandParams += @{"suite" = $LisaTestSuite}
        }
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

        try {
            Report-LisaResults -PipelineName $PipelineName `
                -PipelineBuildNumber $env:BUILD_NUMBER `
                -DBConfigPath $DBConfigPath `
                -IcaLogPath (Resolve-Path $LISA_TEST_RESULTS_REL_PATH)
        } catch {
            Write-Host ("Failed to report stage state with error: {0}" -f @($_))
        }
        Pop-Location
        Copy-Item -Recurse -Force $jobPath .
    }
}

Main
