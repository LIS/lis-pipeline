#
#  When running through Jenkins on Windows, we don't have permissions to manage the hypervisor.
#  We do, however, have access to the network, including the external interface of this machine.
#  Use PSRP to loop back through the eternal interface, where we log in with full privelages, and
#  can manage the hypervisor.
#
#  Jeffrey said this isn't a security hole, and it's the way it's supposed to be done.
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$true)] [string] $script
)

. "C:\Framework-Scripts\secrets.ps1"

$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PASS"
$cred=new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$pw

$s=New-PSSession -ComputerName 169.254.241.55 -Authentication Basic -Credential $cred  -Port 443 -UseSSL -SessionOption $o
if ($? -eq $true) {
    $scriptBlockString = 
    {
        param($sp)
        $psi = New-object System.Diagnostics.ProcessStartInfo 
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false 
        $psi.RedirectStandardOutput = $true 
        $psi.RedirectStandardError = $true 
        $psi.FileName = "powershell.exe"
        $psi.Arguments = @($sp) 
        $process = New-Object System.Diagnostics.Process 
        $process.StartInfo = $psi 

        [void]$process.Start()
        if ($? -eq $true) {
            do
            {
               write-host $process.StandardOutput.ReadLine()
            }
            while (!$process.HasExited) 

            $process.ExitCode
        } else {
            write-host "Error starting process.  Cannot continue..."
            exit 1
        }
    }

    $scriptBlock = [scriptblock]::Create($scriptBlockString)

    $result = Invoke-Command -Session $s -ScriptBlock $scriptBlock -ArgumentList "$script"

    if($result -ne 0) {
        exit 1
    } else {
        exit 0
    }
} else {
    Write-Host "Error creating PSRP session.  Cannot continue.."
    exit 1
}
