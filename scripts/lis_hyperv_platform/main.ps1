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
    [Int]    $VMCheckTimeout = 500,
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
. "$scriptPathParent\JobManager.ps1"

Import-Module "$scriptPath\ini.psm1"

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

function Wait-VMReady {
    param (
        [String] $InstanceName,
        [int] $VMCheckTimeout
    )

    while ($VMCheckTimeout -gt 0) {
        $vmState = $(Get-VM $InstanceName).State
        if ($vmState -ne "Off") {
            Write-Host "Waiting for VM $InstanceName to shut down..."
            Start-Sleep 5
        } else {
            break
        }
        $VMCheckTimeout = $VMCheckTimeout - 5
    }
    if (($VMCheckTimeout -eq 0) -or ($vmState -ne "Off")) {
        throw "VM failed to stop"
    }
    Start-VM $InstanceName
    Write-Host "Retrieving IP for VM $InstanceName..."
    $ip = Get-IP $InstanceName $VMCheckTimeout

    return $ip
}

function Get-Lisa {
    $puttyBinaries = "https://the.earth.li/~sgtatham/putty/0.70/w32/putty.zip"
    if ( Test-Path .\lis-test ) {
        rm -Recurse -Force .\lis-test
    }
    git clone https://github.com/LIS/lis-test.git
    Invoke-WebRequest -Uri $puttyBinaries -OutFile "PuttyBinaries.zip"
    if ($LastExitCode) {
        throw "Failed to download Putty binaries"
    }
    Expand-Archive ".\PuttyBinaries.zip" ".\lis-test\WS2012R2\lisa\bin"

    return ".\lis-test\WS2012R2\lisa\ssh\demo_id_rsa"
}

function Get-Dependencies {
    param(
        [string] $keyPath ,
        [string] $xmlTest
    )
    if ( Test-Path $keyPath ){
        cp "$keyPath" ".\lis-test\WS2012R2\lisa\ssh"
    }
    $keyName = ([System.IO.Path]::GetFileName($keyPath))
    if ( Test-Path $xmlTest ){
        cp $xmlTest ".\lis-test\WS2012R2\lisa\xml"
        $xmlName = ([System.IO.Path]::GetFileName($xmlTest))
    } else {
        $xmlName = $xmlTest
    }
    return ($keyName, $xmlName)
}

function Edit-XmlTest {
    param(
        [string] $vmName ,
        [string] $xmlName ,
        [string] $keyName
    )
    pushd ".\lis-test\WS2012R2\lisa\xml"
    $xml = [xml](Get-Content $xmlName)
    $xml.config.VMs.vm.vmName = $vmName
    $xml.config.VMs.vm.sshKey = $keyName
    $xml.Save("$pwd\$xmlName")
    popd
}

function Main {
    $jobPath = Join-Path $WorkingDirectory $JobId
    Write-Host "Mounting the kernel share..."
    $mountPoint = Mount-Share -SharedStoragePath $SharedStoragePath `
                              -ShareUser $ShareUser -SharePassword $SharePassword
    $KernelVersionPath = Join-Path $env:Workspace $KernelVersionPath
    $kernelPath = Get-IniFileValue -Path $KernelVersionPath -Section "KERNEL_BUILT" -Key "folder"
    $kernelTag = Get-IniFileValue -Path $KernelVersionPath -Section "KERNEL_BUILT" -Key "git_tag"
    if (!$kernelPath -or !$kernelTag) {
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

    $bootLogDirWorkspace = Join-Path (Join-Path $env:Workspace $JobId) "bootlogs"
    New-Item -Type Directory $bootLogDirWorkspace
    $bootLogPath = Join-Path $bootLogDirWorkspace "COM.LOG"
    $scriptBlock = {
        param($InstanceName, $BootLogPath)
        & icaserial.exe READ "\\localhost\pipe\$InstanceName" | Out-File $BootLogPath
    }
    $argumentList = @($InstanceName, $BootLogPath)
    $JobManager = [PSJobManager]::new()
    $JobManager.AddJob($InstanceName, $scriptBlock, $argumentList, $())

    Write-Host "Creating the VM required for LISA to run..."
    & (Join-Path "$scriptPath" "setup_env.ps1") -JobPath $jobPath -VHDPath $vhdPath `
        -KernelPath $kernelPath -InstanceName $InstanceName -IdRSAPub $IdRSAPub `
        -VHDType $VHDType
    if ($LastExitCode) {
        Write-Host $Error[0]
        throw "Creating the LISA VM failed."
    }

    $idRSAPriv = Get-Lisa
    $ip = Wait-VMReady $InstanceName $VMCheckTimeout

    Execute-WithRetry {
        $kernelRevision = & ssh.exe -i $idRSAPriv -o StrictHostKeyChecking=no `
                                    -o ConnectTimeout=10 "root@$ip" "uname -r"
        if ($LASTEXITCODE) {
            throw "Ssh connection failed with error code: $LASTEXITCODE"
        }
        if ($kernelRevision -like "*$kernelTag*") {
            Write-Host "Kernel $kernelRevision matched"
        } else {
            throw "Could not find the kernel: $kernelTag"
        }
    }
    $JobManager.RemoveTopic($InstanceName)

    Write-Host "Starting LISA run..."
    $keyPath = "demo_id_rsa.ppk"
    ($KeyName, $XmlName) = Get-Dependencies $keyPath $XmlTest
    Edit-XmlTest $InstanceName $XmlName $KeyName
    pushd ".\lis-test\WS2012R2\lisa\"
    Write-Host "Started running LISA"
    try {
        & .\lisa.ps1 run xml\$XmlName -dbg 3
        if ($LASTEXITCODE) {
            throw "Failed running LISA with exit code: ${LASTEXITCODE}"
        } else {
            Write-Host "Finished running LISA with exit code: ${LASTEXITCODE}"
        }
    } catch {
        throw $_
    } finally {
        $parentProcessPid = $PID
        $children = Get-WmiObject WIN32_Process | where `
            {$_.ParentProcessId -eq $parentProcessPid -and $_.Name -ne "conhost.exe"}
        foreach ($child in $children) {
            Stop-Process -Force $child.Handle -Confirm:$false `
                         -ErrorAction SilentlyContinue
        }
        popd
    }
}

Main
