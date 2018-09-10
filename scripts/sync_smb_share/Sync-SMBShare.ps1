param(
    [parameter(Mandatory=$true)]
    [String] $LocalSharedStoragePath,
    [parameter(Mandatory=$true)]
    [String] $BaseSharedStoragePath,
    [parameter(Mandatory=$true)]
    [String] $ShareUser,
    [parameter(Mandatory=$true)]
    [String] $SharePassword
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPathParent = (Get-Item $scriptPath ).Parent.FullName

Import-Module "$scriptPathParent\utils\powershell\helpers.psm1"

$AZ_COPY_BINARY = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\AzCopy\AzCopy.exe"
$LOCAL_TO_REMOTE_FOLDER_MAPPINGS = @{
    "stable-kernels" = "stable-kernels";
    "linux-next-kernels" = "upstream-kernel/linux-next";
    "net-next-kernels" = "upstream-kernel/net-next";
    "upstream-stable-kernels" = "upstream-kernel/linux-stable";
}


function Main {
    foreach ($localFolderToSync in $LOCAL_TO_REMOTE_FOLDER_MAPPINGS.keys) {
        try {
            $mappedFolder = $LOCAL_TO_REMOTE_FOLDER_MAPPINGS[$localFolderToSync]
            $localPath = Join-Path $LocalSharedStoragePath $localFolderToSync
            $sharedStoragePath = "${BaseSharedStoragePath}/${mappedFolder}"
            Write-Host "Syncing $sharedStoragePath to $localPath"
            $azCopyResults = & $AZ_COPY_BINARY /Y /S /MT /XO /sourcekey:$SharePassword `
                /source:"${sharedStoragePath}" `
                /dest:"${localPath}" 2>&1
            if ($LASTEXITCODE) {
                throw "Azcopy failed with exit code $LASTEXITCODE and message ${$azCopyResults}"
            } else {
                Write-Host "Azcopy ran with message: $azCopyResults"
            }
        } catch {
            Write-Host "Failed to sync $localFolderToSync"
            Write-Host $_
        }
    }
}

Main