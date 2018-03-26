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
$CURL_PATH = Join-Path $env:ProgramFiles "Git\mingw64\bin\curl.exe"
function Mount-Share {
    param(
        [String] $SharedStoragePath,
        [String] $ShareUser,
        [String] $SharePassword
    )

    # Note(avladu): Replace backslashes with forward slashes
    # for Windows compat
    $SharedStoragePath = $SharedStoragePath.replace('/', '\')

    # Note(avladu): Sometimes, SMB mappings enter into an
    # "Unavailable" state and need to be removed, as they cannot be
    # accessed anymore.
    $smbMappingsUnavailable = Get-SmbMapping -RemotePath $SharedStoragePath `
        -ErrorAction SilentlyContinue | `
        Where-Object {$_.Status -ne "Ok"}
    if ($smbMappingsUnavailable) {
        Write-Host "Removing $smbMappingsUnavailable"
        foreach ($smbMappingUnavailable in $smbMappingsUnavailable) {
            net use /delete $smbMappingUnavailable.LocalPath
        }
    }

    $mountPoint = $null
    $smbMapping = Get-SmbMapping -RemotePath $SharedStoragePath -ErrorAction SilentlyContinue
    if ($smbMapping) {
        Write-Host "Available SMB mappings are: $smbMapping"
        if ($smbMapping.LocalPath -is [array]){
            return $smbMapping.LocalPath[0]
        } else {
            return $smbMapping.LocalPath
        }
    }
    for ([byte]$c = [char]'G'; $c -le [char]'Z'; $c++) {
        $mountPoint = [char]$c + ":"
        try {
            Write-Host "Trying mount point: $mountPoint"
            net.exe use $mountPoint $SharedStoragePath /u:"AZURE\$ShareUser" "$SharePassword" | Out-Null
            if ($LASTEXITCODE) {
                throw "Failed to mount share $SharedStoragePath to $mountPoint."
            } else {
                Write-Host "Successfully mounted SMB share on $mountPoint"
                return $mountPoint
            }
        } catch {
            Write-Host $_
        }
    }
    if (!$mountPoint) {
        Write-Host $Error[0]
        throw "Failed to mount $SharedStoragePath to $mountPoint"
    }
}

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

    & $CURL_PATH -v -X PUT -T $File "$RepoUrl/$RepoType" -H "Authorization: Bearer ${RepoApiKey}" --cacert $RepoCertPath
    if ($LASTEXITCODE) {
        throw "Could not upload file $File to repo!"
    }
}

function Upload-KernelToRepo {
    $mountPathArtifacts = Mount-Share -SharedStoragePath $SmbShareUrl `
        -ShareUser $SmbShareUsername -SharePassword $SmbSharePassword

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
        Upload-FileToKernelRepo -File $fileFullPath -RepoUrl $RepoUrl -RepoType $RepoType `
            -RepoApiKey $RepoApiKey -RepoCertPath $RepoCertPath
    }

    $metaPackages = (Join-Path $smbKernelFolderPath "meta_packages")
    $allFilesMeta = Get-ChildItem $metaPackages -Attributes "!Directory+!System"
    foreach ($file in $allFilesMeta) {
        $fileFullPath = Join-Path $metaPackages $file
        Write-Host "Uploading following file to the repo: $fileFullPath"
        Upload-FileToKernelRepo -File $fileFullPath -RepoUrl $RepoUrl -RepoType $RepoType `
            -RepoApiKey $RepoApiKey -RepoCertPath $RepoCertPath
    }
}


Upload-KernelToRepo
