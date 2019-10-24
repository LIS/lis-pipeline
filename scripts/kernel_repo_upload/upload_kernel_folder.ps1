param(
    [parameter(Mandatory=$true)]
    [String] $KernelFolderPath,
    [parameter(Mandatory=$true)]
    [String] $RepoType,
    [parameter(Mandatory=$true)]
    [String] $RepoUrl,
    [String] $RepoApiKey,
    [String] $RepoCertPath,
    [String] $SASToken
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
    [String] $RepoApiKey,
    [String] $RepoCertPath,
    [String] $SASToken
    )
    if($RepoApiKey -and $RepoCertPath) {
        & $CURL_PATH -k -v --fail -X PUT -T $File "$RepoUrl/$RepoType" `
            -H "Authorization: Bearer ${RepoApiKey}"
            #--cacert $RepoCertPath
    }
    if ($LASTEXITCODE) {
        throw "Could not upload file $File to repo $RepoUrl/$RepoType!"
    }

    if($SASToken) {
        $fileName = (Get-Item $File).Name
        & $CURL_PATH -v --fail -X PUT -T $File "$RepoUrl/$RepoType/$($fileName)$SASToken" `
            -H "x-ms-blob-type: BlockBlob"
    }
    if ($LASTEXITCODE) {
        throw "Could not upload file $File to repo $RepoUrl/$RepoType!"
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
            -RepoCertPath $RepoCertPath -SASToken $SASToken
    }

    $metaPackages = (Join-Path $KernelFolderPath "meta_packages")
    if(Test-Path $metaPackages) {
        $allFilesMeta = Get-ChildItem $metaPackages -Attributes "!Directory+!System"
        foreach ($file in $allFilesMeta) {
            $fileFullPath = Join-Path $metaPackages $file
            Write-Host "Uploading following file to the repo: $fileFullPath"
            Upload-FileToKernelRepo -File $fileFullPath -RepoUrl $RepoUrl `
                -RepoType $RepoType -RepoApiKey $RepoApiKey `
                -RepoCertPath $RepoCertPath -SASToken $SASToken
        }
    }
}


Upload-KernelToRepo