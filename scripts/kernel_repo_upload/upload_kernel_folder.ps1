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
    [String] $RepoCertPath
)

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPathParent = (Get-Item $scriptPath ).Parent.FullName
$CURL_PATH = Join-Path $env:ProgramFiles "Git\mingw64\bin\curl.exe"

Import-Module "$scriptPathParent\utils\powershell\helpers.psm1"

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

    & $CURL_PATH -v --fail -X PUT -T $File "$RepoUrl/$RepoType" `
        -H "Authorization: Bearer ${RepoApiKey}" --cacert $RepoCertPath
    if ($LASTEXITCODE) {
        throw "Could not upload file $File to repo!"
    }
}

function Upload-KernelToRepo {
    if (!(Test-Path "${KernelFolderPath}")) {
        throw "Path $KernelFolderPath does not exist."
    }

    $allFiles = Get-ChildItem $KernelFolderPath -Attributes "!Directory+!System"
    foreach ($file in $allFiles) {
        $fileFullPath = Join-Path $KernelFolderPath $file
        Write-Host "Uploading following file to the repo: $fileFullPath"
        Upload-FileToKernelRepo -File $fileFullPath -RepoUrl $RepoUrl `
            -RepoType $RepoType -RepoApiKey $RepoApiKey `
            -RepoCertPath $RepoCertPath
    }

    $metaPackages = (Join-Path $KernelFolderPath "meta_packages")
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
