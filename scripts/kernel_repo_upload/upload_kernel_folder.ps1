param(
    [parameter(Mandatory=$true)]
    [String] $KernelFolderPath,
    [parameter(Mandatory=$true)]
    [String] $RepoType,
    [parameter(Mandatory=$true)]
    [String] $RepoUrl,
    [parameter(Mandatory=$true)]
    [String] $RepoApiKey,
    [parameter(Mandatory=$true)]
    [String] $RepoCertPath,
    [parameter(Mandatory=$true)]
    [String] $SmbShareUrl,
    [parameter(Mandatory=$true)]
    [String] $SmbShareUsername,
    [parameter(Mandatory=$true)]
    [String] $SmbSharePassword
)

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPathParent = (Get-Item $scriptPath ).Parent.FullName
$CURL_PATH = Join-Path $env:ProgramFiles "Git\mingw64\bin\curl.exe"

. "$scriptPathParent\common_functions.ps1"

function Upload-FileToKernelRepo {
    param(
    [parameter(Mandatory=$true)]
    [String] $File,
    [parameter(Mandatory=$true)]
    [String] $RepoType,
    [parameter(Mandatory=$true)]
    [String] $RepoUrl,
    [parameter(Mandatory=$true)]
    [String] $RepoApiKey,
    [parameter(Mandatory=$true)]
    [String] $RepoCertPath
    )

    & $CURL_PATH -v -X PUT -T $File "$RepoUrl/$RepoType" `
        -H "Authorization: Bearer ${RepoApiKey}" --cacert $RepoCertPath
    if ($LASTEXITCODE) {
        throw "Could not upload file $File to repo!"
    }
}

function Upload-KernelToRepo {
    $mountPathArtifacts = Mount-SMBShare -SharedStoragePath $SmbShareUrl `
        -ShareUser $SmbShareUsername -SharePassword $SmbSharePassword
    $mountPathArtifacts = $mountPathArtifacts.Trim()
    Write-Output "Share has been mounted at mount point: $mountPathArtifacts"

    $KernelFolderPath = $KernelFolderPath.replace("`n", "")
    $smbKernelFolderPath = Join-Path $mountPathArtifacts "${KernelFolderPath}/deb"
    Write-Host ">>>${smbKernelFolderPath}>>>"
    if (!(Test-Path "${smbKernelFolderPath}")) {
        throw "Path $smbKernelFolderPath does not exist."
    }

    $allFiles = Get-ChildItem $smbKernelFolderPath -Attributes "!Directory+!System"
    foreach ($file in $allFiles) {
        $fileFullPath = Join-Path $smbKernelFolderPath $file
        Write-Host "Uploading following file to the repo: $fileFullPath"
        Upload-FileToKernelRepo -File $fileFullPath -RepoUrl $RepoUrl `
            -RepoType $RepoType -RepoApiKey $RepoApiKey `
            -RepoCertPath $RepoCertPath
    }

    $metaPackages = (Join-Path $smbKernelFolderPath "meta_packages")
    $allFilesMeta = Get-ChildItem $metaPackages -Attributes "!Directory+!System"
    foreach ($file in $allFilesMeta) {
        $fileFullPath = Join-Path $metaPackages $file
        Write-Host "Uploading following file to the repo: $fileFullPath"
        Upload-FileToKernelRepo -File $fileFullPath -RepoUrl $RepoUrl `
            -RepoType $RepoType -RepoApiKey $RepoApiKey `
            -RepoCertPath $RepoCertPath
    }
}


Upload-KernelToRepo
