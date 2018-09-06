param (
    [String] $StorageAccName,
    [String] $StorageAccKey,
    [String] $ContainerName,
    [String] $LastVersionFile,
    [String] $Destination
)

function Main {
    if (Test-Path $Destination) {
        Remove-Item -Recurse -Force $Destination
    }
    New-Item -Type Directory -Path $Destination
    
    $lastVersion = Get-Content -Path $LastVersionFile
    if (-not $lastVersion) {
        Write-Host "Latest version file is empty"
    }
    
    $azContext = New-AzureStorageContext -StorageAccountName $StorageAccName 
                    -StorageAccountKey $StorageAccKey
    $azBlobs = Get-AzureStorageBlob -Container $ContainerName -Context $azContext
    $artifacts = $($azBlobs | Where-Object {$_.Name -like "lcow*.tar.gz"})
    
    if ($artifacts) {
        $artifacts = $($artifacts | Sort-Object -Property LastModified -Descending)
        if ($lastVersion -ne $artifacts[0].Name) {
            Get-AzureStorageBlobContent -Container $ContainerName -Blob $artifacts[0].Name 
                -Destination $Destination
        }
    } else {
        Write-Host "Cannot find any matching artifacts"
        exit 1
    }
}

Main