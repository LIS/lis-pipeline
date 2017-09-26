param(
    [String] $JobPath = 'C:\var\lava\tmp\1',
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
    try {
        & $MkisofsPath -V config-2 -r -R -J -l -L -o  $OutputPath $TargetPath 2>&1 | Out-Null
        if ($LastExitCode -ne 0) {
            throw
        }
    } catch {
        return
    }
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

    & 'ssh-keygen.exe' -t rsa -f "$JobPath\$InstanceName-id-rsa" -q -N "''" -C "debian"
    if ($LastExitCode -ne 0) {
        throw
    }

    Write-Host "Creating Configdrive"
    $configDrive = [ConfigDrive]::new("configdrive")
    $configDrive.GetProperties("")
    $configDrive.ChangeProperty("hostname", "pipeline")
    $configDrive.ChangeSSHKey("$JobPath\$InstanceName-id-rsa.pub")
    $configDrive.ChangeUserData("$UserdataPath")
    $configDrive.SaveToNewConfigDrive("$ScriptPath/ConfigDrive-tmp")

    Make-ISO $MkIsoFS "$scriptPath/ConfigDrive-tmp" "$JobPath\configdrive.iso"
    Write-Host "Finished Creating Configdrive"

    Remove-Item -Force -Recurse -Path "$scriptPath/ConfigDrive-tmp"
    Remove-Item -Force "$UserdataPath"
}

Main
