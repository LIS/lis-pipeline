param(
    [String] $VHDPath = "C:\path\to\example.vhdx",
    [String] $UserdataPath = "C:\path\to\userdata.sh",
    [String[]] $KernelURL = @(
        "http://URL/TO/linux-headers.deb",
        "http://URL/TO/linux-image.deb",
        "http://URL/TO/hyperv-daemons.deb"),
    [String] $MkIsoFS = "C:\path\to\mkisofs.exe",
    [String] $InstanceName = "Instance1",
    [String] $KernelVersion = "4.13.2",
    [Int] $VMCheckTimeout = 200
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$JobPath = Split-Path -Parent $VHDPath

. "$scriptPath\retrieve_ip.ps1"

& "$scriptPath\setup_env.ps1" $JobPath $VHDPath $UserdataPath $KernelURL $InstanceName $MkIsoFS
if ($LastExitCode -ne 0) {
    throw
}

$ip = Get-IP $InstanceName $VMCheckTimeout
if ($ip) {
    $throtleTimeStep = 5
    $retryPeriod = 10
    $retryTimes = 10
    while ($retryTimes -gt 0) {
        Write-Host "Trying to connect via SSH to $ip..."
        & ssh.exe -tt -o StrictHostKeyChecking=no -i "$JobPath\$InstanceName-id-rsa" ubuntu@$ip
        if ($LastExitCode) {
            Write-Host "Failed to connect to $ip with error code: $LastExitCode"
        }
        $retryPeriod += $throtleTimeStep
        $retryTimes = $retryTimes - 1
        Start-Sleep $retryPeriod
    }
} else {
    throw "IP for instance $InstanceName not exposed."
}

& "$scriptPath\tear_down_env.ps1" $JobPath $InstanceName 
if ($LastExitCode -ne 0) {
    throw
}

