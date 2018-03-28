param(
    [Parameter(ParameterSetName='lis',Mandatory=$false)][string]$LisUrl,
    [Parameter(ParameterSetName='lis',Mandatory=$true)][string]$AzureToken,
    [Parameter(ParameterSetName='lis',Mandatory=$true)][string]$FullPerfRun,
    [Parameter(ParameterSetName='msft',Mandatory=$false)][string]$KernelVersionPath,
    [parameter(Mandatory=$true)][String] $LocalJenkinsPerfURL,
    [parameter(Mandatory=$true)][String] $LocalJenkinsPerfToken
)

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module "$scriptPath\ini.psm1"

function Trigger-LisPerfRun {
    Write-Host "Triggering performance jobs for LIS"
    Invoke-RestMethod -Method Post `
        -Uri "${LocalJenkinsPerfURL}/buildWithParameters?LIS_URL=${LisUrl}&AZURE_TOKEN=${AzureToken}&`
        FULL_PERF_RUN=${FullPerfRun}&token=${LocalJenkinsPerfToken}"
}

function Trigger-MsftPerfRun {
    Write-Host "Triggering performance jobs for kernel folder: ${KernelVersionPath}"
    Write-Host $KernelVersionPath
    Write-Host (cat $KernelVersionPath)
    $kernelPath = Get-IniFileValue -Path $KernelVersionPath -Section "KERNEL_BUILT" -Key "folder"
    Invoke-RestMethod -Method Post `
        -Uri "${LocalJenkinsPerfURL}/buildWithParameters?KERNEL=${kernelPath}&token=${LocalJenkinsPerfToken}"
}

function Main {
    if ($LisUrl) {
        Trigger-LisPerfRun
    } elseif ($KernelVersionPath) {
        Trigger-MsftPerfRun
    }
}

Main
