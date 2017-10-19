param(
    [String] $SharedStoragePath = "\\shared\storage\path",
    [String] $JobId = "64",
    [String] $UserdataPath = "C:\path\to\userdata.sh",
    [String] $KernelURL = "kernel_url",
    [String] $MkIsoFS = "C:\path\to\mkisofs.exe",
    [String] $InstanceName = "Instance1",
    [String] $KernelVersion = "4.13.2",
    [Int] $VMCheckTimeout = 200
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptPath\retrieve_ip.ps1"

$scriptPath1 = (get-item $scriptPath ).parent.FullName
. "$scriptPath1\common_functions.ps1"

# constants
$KERNEL_ARTIFACTS_URL = @("{0}/hyperv-daemons_{1}_amd64.deb",
                         "{0}/linux-headers-{1}_{1}-10.00.Custom_amd64.deb",
                         "{0}/linux-image-{1}_{1}-10.00.Custom_amd64.deb")
$LAVA_TOOL_DISK = "lava-guest.vhdx"

function Prepare-LocalEnv {
    param(
        [String] $SharedStoragePath,
        [String] $JobId
    )

    $mountPoint = "H:\"
    $localPartition = "C:\"
    $vmDisk = "ubuntu-cloud.vhdx"
    $lavaDisk = "lava-guest.vhdx"

    $path = "/var/lib/lava/dispatcher/tmp/$JobId"
    $remotePath = "$mountPoint\$JobId"
    $localPath = "$localPartition\$path"

    $SharedStoragePath = $SharedStoragePath.Replace("\\", "\")

    net use H: $SharedStoragePath /persistent:NO 2>&1 | Out-Null
    if ($LastExitCode) {
        throw
    }

    Assert-PathExists $remotePath

    New-Item -Path $localPath -ItemType "directory" | Out-Null
    Copy-Item -Path "$remotePath/*" -Destination $localPath -Force -Recurse

    $localVHDPath = (Get-ChildItem -Filter $vmDisk -Path $localPath -Recurse).FullName
    Assert-PathExists $localVHDPath

    $lavaToolDisk = (Get-ChildItem -Filter $LAVA_TOOL_DISK -Path $localPath -Recurse).FullName
    Assert-PathExists $lavaToolDisk

    $remoteVHDPath = (Get-ChildItem -Filter $vmDisk -Path $remotePath -Recurse).FullName
    $remotePath = Split-Path -Parent $remoteVHDPath

    return @($localVHDPath, $lavaToolDisk, $remotePath)
}

function Expand-URL {
    param(
        [String] $KernelUrl,
        [String] $KernelVersion
    )

    $kernelURLExpanded = @()
    foreach ($url in $KERNEL_ARTIFACTS_URL) {
        $kernelURLExpanded += $url -f @($KernelURL, $KernelVersion)
    }

    return $kernelURLExpanded
}

function Main {
    Write-Host "Starting the Main script"
    $localEnvConfig = Prepare-LocalEnv $SharedStoragePath $JobId
    $localVHDPath = $localEnvConfig[0]
    $lavaToolDisk = $localEnvConfig[1]
    $remoteJobFolder = $localEnvConfig[2]

    $expandedURL = Expand-URL $KernelURL $KernelVersion
    $jobPath = Split-Path -Parent $localVHDPath

    Write-Host "Starting Setup-Env script"
    & "$scriptPath\setup_env.ps1" $jobPath $localVHDPath $UserdataPath $expandedURL $InstanceName $MkIsoFS $lavaToolDisk
    if ($LastExitCode) {
        Write-Host $Error[0]
        throw "Setup-Env script failed."
    }

    $ip = Get-IP $InstanceName $VMCheckTimeout
         
    Write-Host "Copying id_rsa from $scriptPath\$InstanceName-id-rsa to $remoteJobFolder\id_rsa"
    Copy-Item "$jobPath\$InstanceName-id-rsa" "$remoteJobFolder\id_rsa"

}

Main
