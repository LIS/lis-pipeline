#!/usr/bin/powershell
#
#  Afterreboot, this script will be executed by runonce.  It checks the booted kernel version against
#  the expected, and returns the result.  If called directly from copy_kernel.ps1, it will be an
#  artificial failure (something happened during install), with the failure point in the argument.
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
# #
param (
    [Parameter(Mandatory=$false)] [string] $failure_point=""
)

Set-Location /HIPPEE/Framework-Scripts
git pull

$global:isHyperV=$true
$global:logFileName="/HIPPEE/report_kernel_version.log"

function callItIn($c, $m) {
    $output_path="c:\temp\$c"
    
    $m | out-file -Append $output_path
    return
}

function phoneHome($m) {
    if ($global:isHyperV -eq $true) {
        invoke-command -session $s -ScriptBlock ${function:callItIn} -ArgumentList $c,$m
    } else {
        $m | out-file $global:logFileName -Append
    }
}

. "/HIPPEE/Framework-Scripts/secrets.ps1"

#
#  Set up the PSRP session
#
nslookup cdmbuildsna01.redmond.corp.microsoft.com
if ($? -eq $false) {
    $global:isHyperV = $false
    phoneHome "It looks like we're in Azure"
} else {
    phoneHome "It looks like we're in Hyper-V"
}

if ($global:isHyperV -eq $true) {
    $o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
    $pw=convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PASS"
    $cred=new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$pw
    $s=new-PSSession -computername lis-f1637.redmond.corp.microsoft.com -credential $cred -authentication Basic -SessionOption $o
}

echo "Starting report-Kernel_version" | out-file $global:logFileName  -Force
#
#  What machine are we on?  This will be our log file name on the host
#
$ourHost=hostname
$c="progress_logs/" + $ourHost

phoneHome "Checking for successful kernel installation"

if ($failure_point -eq "") {
    $kernel_name=uname -r
} else {
    $kernel_name = $failure_point
}
 
if (Get-Item -Path /HIPPEE/expected_version ) {
    $expected=Get-Content /HIPPEE/expected_version
    if ($expected.count -gt 1) {
        $expected = $expected[0]
    }
}

write-host "Got kernel name " $kernel_name
write-host "Execcted kernel name " $expected

if (($kernel_name.CompareTo($expected)) -ne 0) {
    write-verbose "Kernel did not boot into the desired version.  Checking to see if this is a newer version.."
    $boot_again = $false
    $failed = $false
    $oldGrub=get-content /etc/default/grub
    if (Test-Path /bin/rpm) {
        #
        #  rpm-based system
        #
        $kernels = rpm -qa | sls "kernel" | sls 'kernel-[0-9].*'

        $kernelArray_array = @()
        $kernelArray = {$kernelArray_array}.Invoke()
        $kernelArray.Clear()
        
        foreach ($kernel in $kernels) {
            $KernelParts = $Kernel -split '-'
            $vers = $kernelParts[1]
        
            if ($kernelArray -contains $vers) {
            } else {
                $kernelArray += $vers
            }
        }

        foreach ($grubLine in $oldGrub) {
            if ($grubLine -match "GRUB_DEFAULT") {
                $parts = $grubLine -split("=")
        
                [int]$parts[1] = [int]$parts[1] + 1
                if ($parts[1] -ge $kernelArray.count) {
                    write-host "No more kernels to try"
                    $failed = $true
                    break
                } else {
                    write-verbose "Downgrading one level"
                    $boot_again = $true
                }
        
                $grubLine = "GRUB_DEFAULT=" + $parts[1]
            }
        
            $grubLine | out-file -encoding ascii "/tmp/y" -append -force
        }

        copy-Item -Path "/tmp/y" -Destination "/etc/default/grub"
    } else {
        $ver = get-content /HIPPEE/expected_version
        $ver = $ver[0]

        $subs=sls submenu /boot/grub/grub.cfg
        $p1 = ($subs -split "n '")[1]
        $p1 = ($p1 -split "'")[0]
        
        $kerns=sls gnulinux /boot/grub/grub.cfg | select-string $ver | select-string -NotMatch "recovery mode" 
        $p2 = ($kerns -split "option '")[1]
        $p2 =  ($p2 -split "'")[0]

        if ($p1 -ne "" -and $p2 -ne "") {
            $fullName = $p1 + ">" + $p2
        } else {

            Write-Error "Machine did not boot to the right kernel, and the expected kernel is not listed.  Cannot process."
            exit 1
        }

        $alreadyDidThis = "like no, man"
        $alreadyDidThis = sls $fullName /etc/default/grub

        if ([string]::IsNullOrEmpty($alreadyDidThis)) {
            Copy-Item /etc/default/grub /etc/default/grub.orig
            (Get-Content /etc/default/grub) -replace "GRUB_DEFAULT=.*","GRUB_DEFAULT=`"$fullName`"" | Set-Content -Encoding Ascii /etc/default/grub

            @(grub-mkconfig -o /boot/grub/grub.cfg)
            if ($? -eq $false) {
                $failure_point="GrubMkConfig"
                ErrOut($failure_point)
            }
            $boot_again = $true
        } else {
            Write-Error "Machine booted, but has the same OS it had before, even though we directed version $ver.  This machine has failed the BORG"
            $failed = $true
        }
    }
        
    if ($boot_again = $true) {
        copy-Item -Path "/HIPPEE/Framework-Scripts/report_kernel_version.ps1" -Destination "/HIPPEE/runonce.d"
        PhoneHome "Kernel did not come up with the correct version, but the correct version is listed.  "
        reboot
    } elseif ($failed -eq $true) {
        phoneHome "BORG FAILED because no OS version would boot that match expected..."
        phoneHome "Installed version is $kernel_name"
        phoneHome "Expected version is $expected"
        exit 1
    }
}

if (($kernel_name.CompareTo($expected)) -ne 0) {

    #
    #  Switch from the log file to the boot results file and log failure, with both expected and found versions
    #
    $c="boot_results/" + $ourHost
    phoneHome "Failed $kernel_name $expected"

    if ($global:isHyperV -eq $true) {
        remove-pssession $s
    }

    exit 1
} else {
    phoneHome "Passed.  Let's go to Azure!!"

    #
    #  Switch from the log file to the boot results file and log success, with version
    #
    $c="boot_results/" + $ourHost
    phoneHome "Success $kernel_name"

    if ($global:isHyperV -eq $true) {
        remove-pssession $s
    }

    exit 0
}

