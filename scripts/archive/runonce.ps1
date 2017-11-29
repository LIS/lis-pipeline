#!/usr/bin/powershell
#
#  Reused from the StackOverflow article.  Solution by Dennis Williamson
#
#  Place this file in /HIPPEE/Framework_Scripts/
#  Create directory /HIPPEE//runonce.d
#  Add the line "@reboot root /HIPPEE/Framework_Scripts/runonce.ps1" to /etc/crontab
#
#  When there's a script you want to run at the next boot, put it in /HIPPEE/runonce.d.
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#

. /HIPPEE/Framework-Scripts/secrets.ps1

function callItIn($c, $m) {
    $output_path="c:\temp\progress_logs\$c"

    $m | out-file -Append $output_path
    return
}

$global:isHyperV = $false

function phoneHome($m) {
    . /HIPPEE/Framework-Scripts/secrets.ps1
    
    if ($global:isHyperV -eq $true) {
        invoke-command -session $s -ScriptBlock ${function:callItIn} -ArgumentList $c,$m

        if ($? -eq $false)
        {
            #
            #  Error on ps.  Try reconnecting.
            #
            Exit-PSSession $s
            $o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
            $pw=convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PASS"
            $cred=new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$pw
            $s=new-PSSession -computername lis-f1637.redmond.corp.microsoft.com -credential $cred -authentication Basic -SessionOption $o
        }
    } else {
        $output_path="/opt/microsoft/borg_progress.log"

        $m | out-file -Append $output_path
    }
}

#
#  Give the machine 30 seconds to settle down
#
Start-Sleep -Seconds 30

echo "Checking for platform..."
$global:isHyperV=$true
$lookup=nslookup cdmbuildsna01.redmond.corp.microsoft.com
if ($? -eq $false) {
    $global:isHyperV = $false
    echo "It looks like we're in Azure"
} else {
    echo "It looks like we're in Hyper-V"
    $o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
    $pw=convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PASS"
    $cred=new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$pw
    $s=new-PSSession -computername lis-f1637.redmond.corp.microsoft.com -credential $cred -authentication Basic -SessionOption $o
}

#
#  What OS are we on?
#
$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
# $c = $linuxInfo.ID
# $c=$c -replace '"',""
$ourHost=hostname
$c=$ourHost + "_RunOnce"

phoneHome "RunOnce starting up on machine $c"

#
#  Check for the runonce directory
#
if ((Test-Path /HIPPEE/runonce.d) -eq 0) {
    echo "No runonce directory found"
    $LASTEXITCODE = 1
    exit $LASTERRORCODE
}

#
#  If there are entries, execute them....
#

$scriptsArray=@()

Get-ChildItem /HIPPEE/runonce.d -exclude ran |
foreach-Object {
    $script=$_.Name

    echo "Found script $script"
    phoneHome "RunOnce has located $script in execution folder"

    $fullName='/HIPPEE/runonce.d/ran/'+$script

    Move-Item -force $_ $fullName

    $scriptsArray+=$fullName
    phoneHome "Script has been copied to staging folder"

}

foreach ($script in $scriptsArray) {
    phoneHome "RunOnce initiating execution of script $script from staging folder"

    iex $script
    phoneHome "RunOnce execution of script $script complete"
}

if ($global:isHyperV -eq $false) {
    remove-pssession $s
}
