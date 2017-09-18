param(
    [String] $ConfigDrivePath = "C:\path\to\configdrive\",
    [String] $UserdataPath = "C:\path\to\userdata.sh",
    [String[]] $KernelURL = @(
        "http://URL/TO/linux-headers.deb",
        "http://URL/TO/linux-image.deb",
        "http://URL/TO/hyperv-daemons.deb"),
    [String] $MkIsoFS = "C:\path\to\mkisofs.exe"
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptPath\config_drive.ps1"

function Make-ISO {
    param(
        [String] $MkIsoFSPath,
        [String] $TargetPath,
        [String] $OutputPath
    )
    & $MkisofsPath -V config-2 -r -R -J -l -L -o  $OutputPath $TargetPath
}

function Update-URL {
    param(
        [String] $UserdataPath,
        [String] $URL
    )
        (Get-Content $UserdataPath).replace("MagicURL", $URL) `
            | Set-Content $UserdataPath
}

function Preserve-Item {
    param (
        [String] $Path
    )

    Copy-Item -Path $Path -Destination "$Path-tmp"
    return "$Path-tmp"
}


function Main {
    $UserdataPath = Preserve-Item $UserdataPath
    Update-URL $UserdataPath $KernelURL

    & 'ssh-keygen.exe' -t rsa -f "$InstanceName-id-rsa" -q -N "''" -C "ubuntu"

    $configDrive = [ConfigDrive]::new("somethin", $ConfigDrivePath)
    $configDrive.GetProperties()
    $configDrive.ChangeProperty("hostname", "somethingSweet")
    $configDrive.ChangeSSHKey("$InstanceName-id-rsa.pub")
    $configDrive.ChangeUserData($UserdataPath)
    $configDrive.SaveToNewConfigDrive("$ConfigDrivePath-tmp")

    Make-ISO $MkIsoFS "$ConfigDrivePath-tmp" "$ConfigDrivePath.iso"
    Remove-Item -Force -Recurse -Path "$ConfigDrivePath-tmp"
    Remove-Item -Force $UserdataPath
}

Main
