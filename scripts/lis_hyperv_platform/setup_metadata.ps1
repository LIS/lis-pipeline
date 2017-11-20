param(
    [parameter(Mandatory=$true)]
    [String] $JobPath,
    [parameter(Mandatory=$true)]
    [String] $KernelPath,
    [parameter(Mandatory=$true)]
    [String] $IdRSAPub,
    [parameter(Mandatory=$true)]
    [String] $VHDType
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptPath\config_drive.ps1"

$scriptPath1 = (Get-Item $scriptPath ).parent.FullName
. "$scriptPath1\common_functions.ps1"

$ErrorActionPreference = "Stop"

function Make-ISO {
    param(
        [String] $TargetPath,
        [String] $OutputPath
    )
    try {
        $MkIsoFSPath = Resolve-Path "C:\bin\mkisofs.exe"
        & $MkIsoFSPath -o $OutputPath -ldots -allow-lowercase -allow-multidot -quiet -J -r -V "config-2" $TargetPath
        if ($LastExitCode) {
            throw
        }
    } catch {
        return
    }
}

function Main {
    Assert-PathExists $JobPath
    Assert-PathExists $KernelPath

    Write-Host "Creating config drive..."
    $configDrive = [ConfigDrive]::new("configdrive")
    $configDrive.GetProperties("")
    $configDrive.ChangeProperty("hostname", "pipeline")
    $configDrive.ChangeSSHKey($IdRSAPub)
    switch ($VHDType) {
        "ubuntu" {
                $configDrive.ChangeUserData("$scriptPath\install_kernel_deb.sh")
                $kernelFolder = "deb"
            }
        "centos" {
                $configDrive.ChangeUserData("$scriptPath\install_kernel_rhel.sh")
                $kernelFolder = "rpm"
            }
    }
    $tmpConfigDrive = Join-Path $JobPath "ConfigDrive-tmp"
    $finalConfigDrive = Join-Path $JobPath "configdrive.iso"
    $configDrive.SaveToNewConfigDrive($tmpConfigDrive)

    Assert-PathExists $tmpConfigDrive
    Write-Host "Copying kernel artifacts to config drive folder..."
    Copy-Item -Recurse "$KernelPath\$kernelFolder*" $tmpConfigDrive -Force

    Make-ISO -TargetPath $tmpConfigDrive -OutputPath $finalConfigDrive
    Write-Host "Finished Creating Configdrive"
    if (Test-Path $tmpConfigDrive) {
        Remove-Item -Force -Recurse -Path $tmpConfigDrive
    }
}

Main
