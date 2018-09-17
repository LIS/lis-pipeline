param (
    [String] $StorageAccName,
    [String] $StorageAccKey,
    [String] $ContainerName,
    [String] $LastVersionFile,
    [String] $KernelUrl,
    [String] $InitrdUrl,
    [String] $Destination
)

$ErrorActionPreference = "Stop"

$scriptPath = Get-Location
$helpersPath = Join-Path $scriptPath "scripts\utils\powershell\helpers.psm1"
Import-Module $helpersPath

$ARTIFACTS_NAME = "lcow*.tar.bz"
$KERNEL_NAME = "bzimage"
$INITRD_NAME = "core-image-minimal-lcow.cpio.gz"
$BIN_PATH = "C:\Program Files\Git\usr\bin\"
$TEMP_DIR = "D:\lcow-temp"

function Check-AzureShare  {
    param (
        [String] $StorageAccName,
        [String] $StorageAccKey,
        [String] $ContainerName,
        [String] $LastVersionFile,
        [String] $Destination
    )
    
    $lastVersion = ""
    
    if (Test-Path $LastVersionFile) {
        $lastVersion = Get-Content -Path $LastVersionFile -ErrorAction SilentlyContinue
    }
    if (-not $lastVersion) {
        Write-Host "Latest version file is empty"
    }
    
    $azContext = New-AzureStorageContext -StorageAccountName $StorageAccName `
                    -StorageAccountKey $StorageAccKey
    $azBlobs = Get-AzureStorageBlob -Context $azContext -Container $ContainerName
    $artifacts = $($azBlobs | Where-Object {$_.Name -like $ARTIFACTS_NAME})
    
    if ($artifacts) {
        $artifacts = $($artifacts | Sort-Object -Property LastModified -Descending)
        if ($lastVersion -ne $artifacts[0].Name) {
            if (Test-Path $TEMP_DIR) {
                Remove-Item -Recurse -Force $TEMP_DIR
            }
            New-Item -Type Directory -Path $TEMP_DIR
            
            Push-Location $TEMP_DIR

            Get-AzureStorageBlobContent -Container $ContainerName -Blob $artifacts[0].Name `
                -Destination "." -Context $azContext

            $artifactTar = $artifacts[0].Name
            if (-not (Test-Path $artifactTar)) {
                Write-Host "Artifacts failed to download"
                exit 1
            }
            
            $env:Path = "${BIN_PATH};" + $env:Path
            New-Item -Type Directory -Path ".\drop"
            tar -xf "${artifactTar}" -C "./drop"
            Get-ChildItem -Path ".\drop" -Recurse -Include $KERNEL_NAME,$INITRD_NAME | `
                ForEach-Object {Write-Host "Found file: $_";Copy-Item $_ .}

            if (Test-Path ".\${KERNEL_NAME}") {
                Copy-Item ".\${KERNEL_NAME}" "${Destination}\kernel"
            } else {
                throw "Cannot find kernel file"
            }
            if (Test-Path ".\${INITRD_NAME}") {
                gzip -d ".\${INITRD_NAME}"
                $INITRD_NAME = $INITRD_NAME.Replace(".gz", "")
                Copy-Item ".\${INITRD_NAME}" "${Destination}\initrd.img"
            } else {
                throw "Cannot find initrd image"
            }
            Pop-Location
            Set-Content -Value $artifactTar -Path $LastVersionFile
            Set-Content -Value $artifactTar.Split(".")[0] -Path ".\build_name"
        } else {
            Write-Host "No new artifacts found"
            exit 0
        }
    } else {
        Write-Host "Cannot find any matching artifacts"
        exit 1
    }
}

function Download-Artifacts {
    param (
        [String] $KernelUrl,
        [String] $InitrdUrl,
        [String] $Destination
    )

    $kernelDest = Join-Path $Destination "kernel"
    $initrdDest = Join-Path $Destination "initrd.img"

    Download -From $KernelUrl -To $kernelDest
    Download -From $InitrdUrl -To $initrdDest
}

function Main {
    if (Test-Path $Destination) {
        Remove-Item -Recurse -Force $Destination
    }
    New-Item -Type Directory -Path $Destination
    $Destination = Resolve-Path $Destination
    New-Item ".\build_name"

    if ($KernelUrl -and $InitrdUrl) {
        Download-Artifacts -KernelUrl $KernelUrl -InitrdUrl $InitrdUrl `
            -Destination $Destination
    } else {
        Check-AzureShare -StorageAccName $StorageAccName -StorageAccKey $StorageAccKey `
            -ContainerName $ContainerName -LastVersionFile $LastVersionFile `
            -Destination $Destination
    }
}

Main