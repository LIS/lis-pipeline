param(
    [parameter(Mandatory=$true)]
    [String] $JobId,
    [parameter(Mandatory=$true)]
    [String] $InstanceName,
    [parameter(Mandatory=$true)]
    [String] $DistroVersion,
    [parameter(Mandatory=$true)]
    [String] $XmlTest,
    [String] $WorkingDirectory = ".",
    [String] $LISAImagesShareUrl,
    [String] $IdRSAPub,
    [String] $LisaTestParams,
    [String] $LisaTestDependencies,
    [String] $LisUrl,
    [String] $AzureToken,
    [String] $LisaSuite,
    [String] $LisOldUrl,
    [String] $LisaOptionalParams,
    [String] $TestType,
    [String] $LogsPath,
    [String] $Delay
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPathParent = (Get-Item $scriptPath ).Parent.FullName

Import-Module "$scriptPathParent\utils\powershell\helpers.psm1"

function Edit-TestXML {
    param(
        [parameter(Mandatory=$true)]
        [string] $Path,
        [parameter(Mandatory=$true)]
        [string] $VMSuffix,
        [string] $VMgen
    )

    $xmlFullPath = Resolve-Path $Path
    $xml = [xml](Get-Content $xmlFullPath)
    if ($xml.config.VMs.vm -is [array]) {
        foreach ($vmDef in $xml.config.VMs.vm) {
            if ($VMSuffix) {
                $vmDef.vmName = "{0}-{1}" -f @($VMSuffix, $vmDef.vmName)
                if ($vmDef.testParams.param -like "VM2Name*") {
                    $vmDef.testParams.param = "VM2Name={0}-{1}" -f @($VMSuffix, $vmDef.testParams.param.Split("=")[1])
                }
            }
            if ($vmDef.hardware.generation) {
                $vmDef.hardware.generation = $VMgen
            }
        }
    } else {
        if ($xml.config.VMs.vm.hardware.generation) {
            $xml.config.VMs.vm.hardware.generation = $VMgen
        }
        $xml.config.VMS.vm.vmName = $VMSuffix
    }
    $xml.Save($xmlFullPath)
}

function Main {
    Start-Sleep $Delay
    if (!(Test-Path $WorkingDirectory)) {
        New-Item -ItemType directory -Path $WorkingDirectory
    }
    $jobPath = Join-Path -Path (Resolve-Path $WorkingDirectory) `
        -ChildPath $JobId
    
    New-Item -Path $jobPath -Type "Directory" -Force
    $LISAPath = Join-Path $jobPath "lis-test"
    $LISARelPath = Join-Path $LISAPath "WS2012R2\lisa"

    if ($LogsPath -and $TestType) {
        $LogsPath = Join-Path $LogsPath $TestType
        if (!(Test-Path $LogsPath)) {
            New-Item -ItemType Directory -Path $LogsPath -Force
        }
    }
    
    Write-Host "Getting the proper VHD folder name for LISA with $DistroVersion"
    $imageFolder = Join-Path $LISAImagesShareUrl $DistroVersion.split("_")[0]
    $imageFolder = Join-Path $imageFolder $DistroVersion

    Write-Host "Getting LISA code..."
    Get-LisaCode -LISAPath $LISAPath

    Write-Host "Copying lisa dependencies from share"
    Copy-LisaTestDependencies `
        -TestDependenciesFolders @("bin", "Infrastructure", "tools", "ssh") `
        -LISARelPath $LISARelPath -LisaTestDependencies $LisaTestDependencies
    
    $VMgeneration = "1"
    if ($DistroVersion -like "*gen2vm*") {
        $VMgeneration = "2"
    }
    Push-Location "${LISARelPath}\xml"
    try {
        Edit-TestXML -Path $XmlTest -VMSuffix $InstanceName -VMgen $VMgeneration
    } catch {
        throw
    } finally {
        Pop-Location
    }

    Push-Location $LISARelPath
    Write-Host "Started running LISA"
    try {
        $lisaParams = ("LIS_URL='{0}';AZURE_TOKEN={1};LIS_URL_PREVIOUS='{2}'" -f @($LisUrl, $AzureToken, $LisOldUrl))
        if ($LisaOptionalParams) {
            $lisaParams += ";${LisaOptionalParams}"
        }
        # Note(avladu): Lisa requires ErrorActionPreference = Continue,
        # otherwise it will fail to run all the tests.
        $ErrorActionPreference = "Continue"
        $commandParams = @{"cmdVerb" = "run";"cmdNoun" = ".\xml\${XmlTest}";"hvServer" = "localhost"; `
                "dbgLevel" = "5";"CLImageStorDir" = $imageFolder;"testParams" = $lisaParams}
        if ($LisaSuite) {
            $commandParams += @{"suite" = $LisaSuite;"vmName" = $InstanceName;"sshKey" = "rhel5_id_rsa.ppk"; `
                    "os" = "Linux"}
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
        Pop-Location
        Copy-Item -Recurse -Force $LISAPath .
        if ($LogsPath) {
            $LISAPathParent = (Get-Item $LISAPath).Parent.Name
            $LogsPath = Join-Path ${LogsPath} ${LISAPathParent}
            New-Item -ItemType Directory -Path $LogsPath -Force
            $LisaLogPath = Join-Path $LISAPath "WS2012R2\lisa\TestResults\*"
            Copy-Item -Recurse -Force $LisaLogPath $LogsPath
        }
        $parentProcessPid = $PID
        $children = Get-WmiObject WIN32_Process | where `
            {$_.ParentProcessId -eq $parentProcessPid -and $_.Name -ne "conhost.exe"}
        foreach ($child in $children) {
            Stop-Process -Force $child.Handle -Confirm:$false `
                -ErrorAction SilentlyContinue
        }
    }
}

Main
