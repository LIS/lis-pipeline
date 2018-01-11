param(
    [parameter(Mandatory=$true)]
    [String] $KernelVersionPath,
    [parameter(Mandatory=$true)]
    [String] $LocalJenkinsPerfURL,
    [parameter(Mandatory=$true)]
    [String] $LocalJenkinsPerfToken
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module "$scriptPath\ini.psm1"

function Main {
    Write-Host $KernelVersionPath
    Write-Host (cat $KernelVersionPath)
    $kernelPath = Get-IniFileValue -Path $KernelVersionPath `
        -Section "KERNEL_BUILT" -Key "folder"
    Write-Host "Triggering performance jobs for kernel folder: ${kernelPath}"
    Invoke-RestMethod -Method Post `
        -Uri "${LocalJenkinsPerfURL}/buildWithParameters?KERNEL=${kernelPath}&token=${LocalJenkinsPerfToken}"
}

Main
