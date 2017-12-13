param(
    [parameter(Mandatory=$true)]
    [String] $SharedStoragePath,
    [parameter(Mandatory=$true)]
    [String] $ShareUser,
    [parameter(Mandatory=$true)]
    [String] $SharePassword,
    [parameter(Mandatory=$true)]
    [String] $JobId,
    [parameter(Mandatory=$true)]
    [String] $InstanceName,
    [parameter(Mandatory=$true)]
    [String] $VHDType,
    [parameter(Mandatory=$true)]
    [String] $IdRSAPub,
    [parameter(Mandatory=$true)]
    [String] $XmlTest,
    [Int]    $VMCheckTimeout = 300,
    [String] $WorkingDirectory = ".",
    [String] $QemuPath = "C:\bin\qemu-img.exe",
    [String] $UbuntuImageURL = "https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img",
    [String] $CentosImageURL = "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2",
    [String] $KernelVersionPath = "scripts\package_building\kernel_versions.ini"
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptPath\retrieve_ip.ps1"
$scriptPathParent = (Get-Item $scriptPath ).Parent.FullName
. "$scriptPathParent\common_functions.ps1"
Import-Module "$scriptPath\ini.psm1"

function Mount-Share {
    param(
        [String] $SharedStoragePath,
        [String] $ShareUser,
        [String] $SharePassword
    )

    $mountPoint = $null
    $smbMapping = Get-SmbMapping -RemotePath $SharedStoragePath -ErrorAction SilentlyContinue
    if ($smbMapping) {
        if ($smbMapping.LocalPath -is [array]){
            return $smbMapping.LocalPath[0]
        } else {
            return $smbMapping.LocalPath
        }
    }
    for ([byte]$c = [char]'G'; $c -le [char]'Z'; $c++) {
        $mountPoint = [char]$c + ":"
        try {
            net.exe use $mountPoint $SharedStoragePath /u:"AZURE\$ShareUser" "$SharePassword" | Out-Null
            if ($LASTEXITCODE) {
                throw "Failed to mount share $SharedStoragePath to $mountPoint."
            } else {
                Write-Host "Successfully monted SMB share on $mountPoint"
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

function Get-VHD {
    param(
        [String] $VHDType,
        [String] $JobPath
    )

    switch ($VHDType) {
        "ubuntu" {$downloadURL = $UbuntuImageURL}
        "centos" {$downloadURL = $CentosImageURL}
    }

    $vhdPath = Join-Path $JobPath "image.vhdx"
    $fileType = [System.IO.Path]::GetExtension($downloadURL)
    $downloadedImage = Join-Path $JobPath "image$fileType"
    Write-Host "Downloading image file from $downloadURL to $downloadedImage..."
    (New-Object System.Net.WebClient).DownloadFile($downloadURL, $downloadedImage)

    $QemuPath = Resolve-Path $QemuPath
    Write-Host "Converting image file from $downloadedImage to $vhdPath..."
    & $QemuPath convert $downloadedImage -O vhdx $vhdPath
    if ($LASTEXITCODE) {
        throw "Qemu failed to convert $downloadedImage to $vhdPath."
    }
    return $vhdPath
}

function Main {
    $jobPath = Join-Path $WorkingDirectory $JobId
    Write-Host "Mounting the kernel share..."
    $mountPoint = Mount-Share -SharedStoragePath $SharedStoragePath `
                              -ShareUser $ShareUser -SharePassword $SharePassword
    $KernelVersionPath = Join-Path $env:Workspace $KernelVersionPath
    $kernelPath = Get-IniFileValue -Path $KernelVersionPath -Section "KERNEL_BUILT" -Key "folder"
    if (!$kernelPath) {
        throw "Kernel folder cannot be empty."
    }
    Write-Host "Using kernel folder name: $kernelPath."
    $kernelPath = Join-Path $mountPoint $KernelPath
    Assert-PathExists $kernelPath

    if (!(Test-Path $WorkingDirectory)) {
        New-Item -Path $jobPath -Type Directory -Force | Out-Null
    }
    $WorkingDirectory = Resolve-Path $WorkingDirectory
    New-Item -Path $jobPath -Type "Directory" -Force | Out-Null

    $vhdPath = Get-VHD -VHDType $VHDType -JobPath $jobPath

    Write-Host "Creating the VM required for LISA to run..."
    & (Join-Path "$scriptPath" "setup_env.ps1") -JobPath $jobPath -VHDPath $vhdPath `
        -KernelPath $kernelPath -InstanceName $InstanceName -IdRSAPub $IdRSAPub `
        -VHDType $VHDType
    if ($LastExitCode) {
        Write-Host $Error[0]
        throw "Creating the LISA VM failed."
    }

    Write-Host "Retrieving IP for VM $InstanceName..."
    $ip = Get-IP $InstanceName $VMCheckTimeout
    Start-Sleep 20

    Write-Host "Starting LISA run..."
    & "$scriptPath\lisa_run.ps1" -WorkDir "." -VMName $InstanceName -KeyPath "demo_id_rsa.ppk" -XmlTest $XmlTest
}

Main
