param(
    [String] $InstanceName = "Instance1",
    [String] $KernelVersion = "4.13.2",
    [Int] $VMCheckTimeout = 100
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPath = (get-item $scriptPath ).parent.FullName
. "$scriptPath\backend.ps1"

function Main {
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

    $kernel = & ssh.exe -oStrictHostKeyChecking=no -i "$InstanceName-id-rsa" "ubuntu@$ip" 'uname -r'

    if ($KernelVersion -ne $kernel) {
        throw "Kernel missmatch Expected kernel: $KernelVersion != Actual kernel : $kernel"
    } else {
        Write-Host "SUCCESS" -ForegroundColor Green
    }
}

Main
