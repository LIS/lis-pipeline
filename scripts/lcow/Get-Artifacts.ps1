param (
    [String] $ArtifactsDestination,
    [String] $BuildIdDestination,
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
$PACKAGES_NAME = "rpm.tgz"
$BUILD_ID = "metadata.txt"
$PACKAGES_REL_PATH=".\tmp\deploy\rpm\lcow\kernel*"
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
        [String] $Destination,
        [String] $BuildIdDestination
    )
    
    if (Test-Path $TEMP_DIR) {
        Remove-Item -Recurse -Force $TEMP_DIR
    }
    New-Item -Type Directory -Path $TEMP_DIR

    Push-Location $TEMP_DIR

    vsts login --token $Token
    Write-Host "vsts package universal download --instance $Instance --feed $Feed --name $PackageName --version $Version --path ."
    vsts package universal download --instance $Instance --feed $Feed --name $PackageName --version $Version --path "."

    Get-ChildItem -Path "." -Recurse -Include $KERNEL_NAME,$INITRD_NAME,$BUILD_ID,$PACKAGES_NAME | `
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
    if (Test-Path ".\${BUILD_ID}") {
        Write-Host "Using unique build id"
        $buildID = Get-Content ".\${BUILD_ID}"
        $identifier = @{}
        $buildID.split(";") | foreach-object {
                                                if ($_ -ne "") {
                                                    $identifier[$_.Split("=")[0]] = $_.Split("=")[1]
                                                }
                                             }
        $id = "$($identifier['CDP_BUILD_TYPE'])_$($identifier['BUILD_SOURCEBRANCHNAME'])_$($identifier['CDP_BUILD_NUMBER'])"
        Set-Content -Value $id -Path $BuildIdDestination
        if ($identifier['BUILD_BUILDID'] -ne $null) {
            $destDir = Split-Path -Parent $BuildIdDestination
            $urlID = Join-Path $destDir "urlID.txt"
            Set-Content -Value $identifier['BUILD_BUILDID'] -Path $urlID
        }
    } else {
        Write-Host "Using package version"
        Set-Content -Value $Version -Path $BuildIdDestination
    }
    if (Test-Path ".\${PACKAGES_NAME}") {
        tar -xzf ".\${PACKAGES_NAME}"
        if (Test-Path $PACKAGES_REL_PATH) {
            $packageDest = Join-Path $Destination "packages"
            New-Item -Type Directory -Path $packageDest
            Copy-Item ".\${PACKAGES_REL_PATH}" $packageDest
        } else {
            throw "Cannot find kernel packages in archive"
        }
    } else {
        throw "Cannot find packages archive"
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
        [String] $ArtifactsDestination,
        [String] $BuildIdDestination
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
            -Instance $Instance -Destination $ArtifactsDestination `
            -BuildIdDestination $BuildIdDestination
        Set-Content -Value $latestVersion -Path $VersionsFile
    } else {
        Write-Host "Cannot find newer version"
    }
}

# Direct Download from URL

function Download-Artifacts {
    param (
        [String] $KernelUrl,
        [String] $InitrdUrl,
        [String] $Destination,
        [String] $BuildIdDestination
    )

    $kernelDest = Join-Path $Destination "kernel"
    $initrdDest = Join-Path $Destination "initrd.img"

    Download -From $KernelUrl -To $kernelDest
    Download -From $InitrdUrl -To $initrdDest

    Set-Content -Value "manual-run" -Path $BuildIdDestination
}

# Main

function Main {
    if (Test-Path $ArtifactsDestination) {
        Remove-Item -Recurse -Force $ArtifactsDestination
    }
    if (Test-Path $BuildIdDestination) {
        Remove-Item -Force $BuildIdDestination
    }
    
    New-Item -Path $BuildIdDestination
    New-Item -Type Directory -Path $ArtifactsDestination
    $ArtifactsDestination = Resolve-Path $ArtifactsDestination
    $BuildIdDestination = Resolve-Path $BuildIdDestination

    if ($KernelUrl -and $InitrdUrl) {
        Download-Artifacts -KernelUrl $KernelUrl -InitrdUrl $InitrdUrl `
            -Destination $ArtifactsDestination `
            -BuildIdDestination $BuildIdDestination
    } else {
        Get-UniversalPackage -Username $UserName -Token $Token `
            -URL $VstsUrl -Feed $VstsFeed -Instance $VstsInstance `
            -PackageName $PackageName -VersionsFile $VersionsFile `
            -ArtifactsDestination $ArtifactsDestination `
            -BuildIdDestination $BuildIdDestination
    }
}

Main
