param(
    [parameter(Mandatory=$true)]
    [String] $SharedStoragePath,
    [parameter(Mandatory=$true)]
    [String] $Location,
    [parameter(Mandatory=$true)]
    [String] $Destination
)

$ErrorActionPreference = "Stop"

function Mount-Share {
    param(
        [String] $SharedStoragePath,
        [String] $ShareUser,
        [String] $SharePassword
    )

    # Note(avladu): Sometimes, SMB mappings enter into an
    # "Unavailable" state and need to be removed, as they cannot be
    # accessed anymore.
    $smbMappingsUnavailable = Get-SmbMapping -RemotePath $SharedStoragePath `
        -ErrorAction SilentlyContinue | Where-Object {$_.Status -eq "Unavailable"}
    if ($smbMappingsUnavailable) {
        foreach ($smbMappingUnavailable in $smbMappingsUnavailable) {
            net use /delete $smbMappingUnavailable.LocalPath
        }
    }

    $mountPoint = $null
    $smbMapping = Get-SmbMapping -RemotePath $SharedStoragePath -ErrorAction SilentlyContinue
    if ($smbMapping) {
        if ($smbMapping.LocalPath -is [array]){
            return $smbMapping.LocalPath[0]
        } else {
            return $smbMapping.LocalPath
        }
    }
    if (!$ShareUser) {
        Write-Host "No share user provided"
        $auth = ""
    } else {
        $auth = "/u:`"AZURE\$ShareUser`" $SharePassword"
    }
    for ([byte]$c = [char]'G'; $c -le [char]'Z'; $c++) {
        $mountPoint = [char]$c + ":"
        try {
            net.exe use $mountPoint $SharedStoragePath $auth | Out-Null
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

function Copy-Artifacts {
    Param(
        [Parameter(Mandatory=$true)]
        [String] $From,
        [Parameter(Mandatory=$true)]
        [String] $To
    )

    if (Test-Path $To) {
        Write-Host "Destination folder already exists, incrementing by 1."
        $testName = $To
        for($i = 1; Test-Path $testName; ++$i) {
            $testName = $To + "-$i"
        }
        $To = $testName
    }

    try {
        Copy-Item -Path $From -Destination $To -Recurse
    } catch {
        Write-Host "Couldn't copy the artifacts"
        Write-Host $_
        return
    }

    Write-Host "Sucesfully copied artifacts to storage."
}

function Main {
    Write-Host "Mounting share"
    $mountPathArtifacts = Mount-Share $SharedStoragePath
    $dest = Join-Path -Path $mountPathArtifacts -ChildPath $Destination
    Copy-Artifacts $Location $dest
}

function Main {
    Write-Host "Mounting share"
    $mountPathArtifacts = Mount-Share $SharedStoragePath
    $date = Get-Date -UFormat "%Y-%m-%d"
    $leaf = Split-Path -Path $Destination -Leaf
    $dest = [String]::Format("{0}\{1}-lcow-{2}", $mountPathArtifacts, `
                                                 $date, $leaf)
    Write-Host "Dest is $dest"
    Copy-Artifacts $Location $dest
}

Main
