$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPath = (get-item $scriptPath ).parent.FullName
. "$scriptPath\backend.ps1"

function Get-IP {
    $backend = [HypervBackend]::new(@("localhost"))
    $instance = [HypervInstance]::new($backend, $InstanceName, "")

    while ($VMCheckTimeout -gt 0) {
        $ip = $instance.GetPublicIP()
        if ([String]::IsNullOrWhiteSpace($ip)) {
            Start-Sleep 5
        } else {
            break
        }
        $VMCheckTimeout = $VMCheckTimeout - 5
    }

    return $ip
}
