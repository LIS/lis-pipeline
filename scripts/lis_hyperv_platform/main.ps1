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
    [String] $DBConfigPath
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPathParent = (Get-Item $scriptPath ).Parent.FullName

$LISA_TEST_RESULTS_REL_PATH = ".\TestResults\*\ica.log"
$DB_CONFIG_REL_PATH = ".\db.config"
$DB_RESULTS_REL_PATH = ".\tests.json"
$PYTHON_PATH = Join-Path "${env:SystemDrive}" "Python27\python.exe"
$RESULT_PARSER_PATH = Join-Path $scriptPathParent ".\reporting\parser.py"

. "$scriptPath\retrieve_ip.ps1"
. "$scriptPathParent\common_functions.ps1"
. "$scriptPathParent\JobManager.ps1"

Import-Module "$scriptPath\ini.psm1"

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
        throw "${LisaTestDependencies} path does not exist!"
    }
    foreach ($folder in $TestDependenciesFolders) {
        $LisaDepPath = Join-Path $LisaTestDependencies $folder
        Copy-Item -Force `
            -Recurse -Path $LisaDepPath `
            -Destination $LISARelPath
    } 
}

function Edit-TestXML {
    param(
        [parameter(Mandatory=$true)]
        [string] $Path,
        [parameter(Mandatory=$true)]
        [string] $VMSuffix,
        [string] $KeyName
    )
    $xmlFullPath = Join-Path $PWD $Path
    if (!(Test-Path $xmlFullPath)) {
        throw "Test XML $xmlFullPath does not exist."
    }
    $xml = [xml](Get-Content $xmlFullPath)
    $index = 0
    if ($xml.config.VMs.vm -is [array]) {
        foreach ($vmDef in $xml.config.VMs.vm) {
            $xml.config.VMS.vm[$index].vmName = $vmDef.vmName + $VMSuffix
            if ($KeyName) {
                $xml.config.VMS.vm[$index].sshKey = $KeyName
            }
            $testParams = $vmDef.testParams
            if ($testParams) {
                $paramIndex = 0
                foreach ($testParam in $testParams.param) {
                    if ($testParam -like "VM2NAME=*") {
                        $testParams.ChildNodes.Item($paramIndex)."#text" = `
                            $testParam + $VMSuffix
                    }
                    $paramIndex = $paramIndex + 1
                }
            }
            $index = $index + 1
        }
    } else {
        $xml.config.VMS.vm.vmName = $xml.config.VMS.vm.vmName + $VMSuffix
        if ($KeyName) {
            $xml.config.VMS.vm.sshKey = $KeyName
        }
    }
    $xml.Save($xmlFullPath)
}

function Parse-IcaLog {
    param(
        [parameter(Mandatory=$true)]
        [String] $IcaLogPath
    )

    try {
        $allTestLines = Get-Content $IcaLogPath | `
            Where-Object {$_ -match '(^Test\sResults\sSummary$)|(^\s\s\s\sTest\s)'}
        if ($allTestLines.Count -eq 0) {
            throw "IcaLogPath $IcaLogPath does not contain test results summary."
        }
        return ($allTestLines | `
            Where-Object{$_ -match '(:\sFailed$)|(:\sAborted$)'}).Count
    } catch {
        Write-Host "Failure to parse test results file."
        throw $_
    }
}

function Report-LisaResults {
    param(
        [parameter(Mandatory=$true)]
        [String] $PipelineName,
        [parameter(Mandatory=$true)]
        [String] $PipelineBuildNumber,
        [parameter(Mandatory=$true)]
        [String] $DBConfigPath,
        [parameter(Mandatory=$true)]
        [String] $IcaLogPath
    )
    $pipelineStageStatus = Parse-IcaLog -IcaLogPath $IcaLogPath
    $templateJSON = @'
[{{
        "PipelineName": "{0}",
        "PipelineBuildNumber": {1},
        "FuncTestsFailedOnLocal": {2}
}}]
'@
    $templateJSON = $templateJSON -f @($PipelineName,
           $PipelineBuildNumber, $pipelineStageStatus
       )

    Write-Host $templateJSON
    Write-Output $templateJSON | Out-File -Encoding ascii $DB_RESULTS_REL_PATH
    Copy-Item -Force $DBConfigPath $DB_CONFIG_REL_PATH
    & $PYTHON_PATH $RESULT_PARSER_PATH
}

function Main {
    $KernelVersionPath = Join-Path $env:Workspace $KernelVersionPath
    $kernelFolder = Get-IniFileValue -Path $KernelVersionPath `
        -Section "KERNEL_BUILT" -Key "folder"
    if (!$kernelFolder) {
        throw "Kernel folder cannot be empty."
    }
    $jobPath = Join-Path -Path (Resolve-Path $WorkingDirectory) -ChildPath $JobId
    New-Item -Path $jobPath -Type "Directory" -Force
    if (!(Test-Path $WorkingDirectory)) {
        New-Item -ItemType "Directory" -Path $WorkingDirectory
    }
    $LISAPath = Join-Path $jobPath "lis-test"
    $LISARelPath = Join-Path $LISAPath "WS2012R2\lisa"

    Write-Host "Getting the proper VHD folder name for LISA with ${OsVersion} and ${VHDType}"
    $imageFolder = Join-Path $LISAImagesShareUrl ("{0}\{0}_{1}" -f @($VHDType, $OsVersion))
    Write-Host "Getting LISA code..."
    Get-LisaCode -LISAPath $LISAPath

    Write-Host "Copying lisa dependencies from share"
    Copy-LisaTestDependencies `
        -TestDependenciesFolders @("bin", "Infrastructure", "tools", "ssh") `
        -LISARelPath $LISARelPath

    Push-Location "${LISARelPath}\xml"
    try {
        Edit-TestXML -Path $XmlTest -VMSuffix $InstanceName
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
        & .\lisa.ps1 -cmdVerb run -cmdNoun ".\xml\${XmlTest}" -dbgLevel 6 `
            -CLImageStorDir $imageFolder -testParams $lisaParams
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
        Copy-Item -Recurse -Force $LISAPath .
    }
}

Main
