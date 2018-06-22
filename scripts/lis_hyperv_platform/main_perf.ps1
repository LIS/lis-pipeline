param(
    [parameter(Mandatory=$true)]
    [String] $JobId,
    [parameter(Mandatory=$true)]
    [String] $InstanceName,
    [parameter(Mandatory=$true)]
    [String] $VHDType,
    [parameter(Mandatory=$true)]
    [String] $XmlTest,
    [String] $WorkingDirectory = ".",
    [String] $KernelVersionPath,
    [String] $OsVersion,
    [String] $LISAImagesShareUrl,
    [String] $LisaTestDependencies,
    [String] $LocalKernelFolder,
    [String] $LisaPerfOptions,
    [String] $VHDDestination
)

$ErrorActionPreference = "Stop"

$gitPath = 'C:\Program Files\Git\bin\git.exe'
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPathParent = (Get-Item $scriptPath ).Parent.FullName

$LISA_TEST_RESULTS_REL_PATH = ".\TestResults\*\ica.log"

. "$scriptPath\XMLParser.ps1"
Import-Module "$scriptPathParent\utils\powershell\ini.psm1"
Import-Module "$scriptPathParent\utils\powershell\helpers.psm1"

function Edit-PerfXML{
    param(
        [String] $Path,
        [String] $Options
    )

    $parser = [XMLParser]::new($Path)
    foreach ($option in ($Options.Split(";"))) {
        $parser.ChangeXML($option)
    }
    $parser.Save($Path)
}

function Run-Lisa {
    param(
        [parameter(Mandatory=$true)]
        [String] $LisaPath,
        [parameter(Mandatory=$true)]
        [hashtable] $LisaParams,
        [String] $LisaLogPath
    )

    Push-Location $LisaPath
    try {
        $ErrorActionPreference = "Continue"
        & .\lisa.ps1 @LisaParams
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
        if ($LisaLogPath) {
            Copy-Item -Recurse -Force $LisaLogPath .
        }
    }
}

function Main {
    if ($KernelVersionPath) {
        $KernelVersionPath = Join-Path $env:Workspace $KernelVersionPath
        $kernelName = Get-IniFileValue -Path $KernelVersionPath `
            -Section "KERNEL_BUILT" -Key "folder"
    }
    if (!(Test-Path $LocalKernelFolder)) {
        throw "Kernel folder does not exist"
    } else {
        $LocalKernelFolder = Resolve-Path $LocalKernelFolder
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
    Get-LisaCode -LISAPath $LISAPath -GitPath $gitPath

    Write-Host "Copying lisa dependencies from share"
    Copy-LisaTestDependencies `
        -LisaTestDependencies $LisaTestDependencies `
        -TestDependenciesFolders @("bin", "Infrastructure", "tools", "ssh") `
        -LISARelPath $LISARelPath

    # Edit XML
    if ([String]::IsNullOrWhiteSpace($VHDDestination)) {
        Push-Location $LISARelPath
        Write-Host "Editing XML for Perf"
        $xmlPath = Resolve-Path -Path ".\xml\${XmlTest}"
        Edit-PerfXML -Path $xmlPath -Options $LisaPerfOptions
        Write-Host "Finished editing XML for Perf"    
        Pop-Location
    }

    # Image Build

    if ([String]::IsNullOrWhiteSpace($VHDDestination)) {
        $VhdDestination = Join-Path $jobPath "vhd-destination"
        New-Item -ItemType "Directory" -Path $VhdDestination
    }
    $vhdName = "$kernelName.vhdx"

    $testParams = ("distro={0};vhdStore={1};uploadName={2};localPath={3}" `
        -f @($VHDType, $VHDDestination, $vhdName, $LocalKernelFolder))
    $LisaTestParams = @{"cmdVerb" = "run";"cmdNoun" = ".\xml\build-vhdx-msft.xml"; `
        "dbgLevel" = "9";"CLImageStorDir" = $imageFolder;"testParams" = $testParams}
    Run-Lisa -LisaPath $LISARelPath -LisaParams $LisaTestParams

    # Perf Run
    if ([String]::IsNullOrWhiteSpace($VHDDestination)) {
        $NetPath = ("\\{0}\{1}$\{2}" `
            -f @($(hostname), $VhdDestination.split(":")[0], $VhdDestination.split(":")[1]))
        $LisaTestParams = @{"cmdVerb" = "run";"cmdNoun" = ".\xml\${XmlTest}"; `
            "dbgLevel" = "6";"CLImageStorDir" = $NetPath}
        Run-Lisa -LisaPath $LISARelPath -LisaParams $LisaTestParams -LisaLogPath $jobPath
    }

    # Cleanup

    Remove-Item -Recurse -Force $jobPath
}

Main
