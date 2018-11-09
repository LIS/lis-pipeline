param (
    [String] $ArtifactsDestination,
    [String] $UserName,
    [String] $Token,
    [String] $VstsUrl,
    [String] $VstsInstance,
    [String] $VstsFeed,
    [String] $PackageName,
    [String] $VersionsFile,
    [String] $KernelUrl,
    [String] $InitrdUrl   
)

$scriptPath = Get-Location
$helpersPath = Join-Path $scriptPath "scripts\utils\powershell\helpers.psm1"
Import-Module $helpersPath

$KERNEL_NAME = "bzimage"
$INITRD_NAME = "core-image-minimal-lcow.cpio.gz"
$BIN_PATH = "C:\Program Files\Git\usr\bin\"
$VSTS_PATH = "C:\Program Files (x86)\Microsoft SDKs\VSTS\CLI\wbin\"
$env:Path = "${BIN_PATH};${VSTS_PATH};" + $env:Path
$TEMP_DIR = "D:\lcow-temp"

# Universal Package Watcher

function Get-AuthHeader {
    param (
        [String] $Username,
        [String] $Token
    )

    $pair = "${Username}:${Token}"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64Creds = [System.Convert]::ToBase64String($bytes)

    $authHeader = @{Authorization = "Basic ${base64Creds}"}
    return $authHeader
}

function Get-LatestVersion {
    param (
        [String] $Username,
        [String] $Token,
        [String] $URL,
        [String] $PackageName
    )

    $authHeader = Get-AuthHeader -Username $Username -Token $Token
    $rawJson = Invoke-WebRequest -uri $URL -Headers $authHeader -UseBasicParsing

    $json = $(ConvertFrom-Json $rawJson.content)

    foreach ($package in $json.value) {
        if ($package.name -eq $PackageName) {
            $packageVersion = $package.versions.version
            break
        }
    }

    if (-not $packageVersion) {
        throw "Cannot find version for package: ${PackageName}"
    }

    return $packageVersion
}

function Download-VstsArtifacts {
    param (
        [String] $Token,
        [String] $Feed,
        [String] $Instance,
        [String] $PackageName,
        [String] $Version,
        [String] $Destination
    )
    
    if (Test-Path $TEMP_DIR) {
        Remove-Item -Recurse -Force $TEMP_DIR
    }
    New-Item -Type Directory -Path $TEMP_DIR

    Push-Location $TEMP_DIR

    vsts login --token $Token
    Write-Host "vsts package universal download --instance $Instance --feed $Feed --name $PackageName --version $Version --path ."
    vsts package universal download --instance $Instance --feed $Feed --name $PackageName --version $Version --path "."

    Get-ChildItem -Path "." -Recurse -Include $KERNEL_NAME,$INITRD_NAME | `
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
}

function Get-UniversalPackage {
    param (
        [String] $Username,
        [String] $Token,
        [String] $URL,
        [String] $Feed,
        [String] $Instance,
        [String] $PackageName,
        [String] $VersionsFile,
        [String] $ArtifactsDestination
    )

    $latestVersion = Get-LatestVersion -Username $Username -Token $Token `
        -URL $URL -PackageName $PackageName

    $localVersion = ""
    if ($VersionsFile -and (Test-Path $VersionsFile)) {
        $localVersion = Get-Content $VersionsFile
    } else {
        Write-Host "Warning: Cannot find versions file at path: ${VersionsFile}"
    }
    if (-not $localVersion) {
        Write-Host "Warning: Cannot find local version"
        $localVersion = "0.0.0"
    }

    if ($latestVersion -gt $localVersion) {
        Write-Host "Newer Version: $latestVersion"
        Download-VstsArtifacts -Token $Token -Feed $Feed `
            -PackageName $PackageName -Version $latestVersion `
            -Instance $Instance -Destination $ArtifactsDestination
        Set-Content -Value $latestVersion -Path $VersionsFile
        Set-Content -Value "lcow-${latestVersion}" -Path ".\build_name"
    } else {
        Write-Host "Cannot find newer version"
    }
}

# Direct Download from URL

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

    Set-Content -Value "manual-run" -Path ".\build_name"
}

# Main

function Main {
    if (Test-Path $ArtifactsDestination) {
        Remove-Item -Recurse -Force $ArtifactsDestination
    }

    New-Item -Type Directory -Path $ArtifactsDestination
    $ArtifactsDestination = Resolve-Path $ArtifactsDestination
    New-Item ".\build_name"

    if ($KernelUrl -and $InitrdUrl) {
        Download-Artifacts -KernelUrl $KernelUrl -InitrdUrl $InitrdUrl `
            -Destination $ArtifactsDestination
    } else {
        Get-UniversalPackage -Username $UserName -Token $Token `
            -URL $VstsUrl -Feed $VstsFeed -Instance $VstsInstance `
            -PackageName $PackageName -VersionsFile $VersionsFile `
            -ArtifactsDestination $ArtifactsDestination
    }
}

Main
