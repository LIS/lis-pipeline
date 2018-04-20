$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPathBackend = (Get-Item $scriptPath ).parent.FullName
. "$scriptPathBackend\backend.ps1"
 
function Get-IP {
    param(
        [String] $InstanceName,
        [Int]    $VMCheckTimeout
    )

    $backend = [HypervBackend]::new(@("localhost"))
    $instance = [HypervInstance]::new($backend, $InstanceName, "")

    while ($VMCheckTimeout -gt 0) {
        $ip = $instance.GetPublicIP()
        if ([String]::IsNullOrWhiteSpace($ip)) {
            Write-Host "Failed to get ip"
            Start-Sleep 5
        } else {
            break
        }
        $VMCheckTimeout = $VMCheckTimeout - 5
    }
    if (($VMCheckTimeout -eq 0) -or !$ip) {
        throw "Failed to get an IP."
    }

    return $ip
}
