param (
    [Parameter(Mandatory=$false)] [string[]] $requestedNames,

    [Parameter(Mandatory=$false)] [string] $destSA="smokesrc",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",

    [Parameter(Mandatory=$false)] [string] $suffix="-Runonce-Primed.vhd",

    [Parameter(Mandatory=$false)] [string] $command="unset",
    [Parameter(Mandatory=$false)] [string] $asRoot="false",

    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [int] $retryCount=2
)

$destSA = $destSA.Trim()
$destRG = $destRG.Trim()
$suffix = $suffix.Trim()
$asRoot = $asRoot.Trim()
$location = $location.Trim()
$requestedNames = $requestedNames.Trim()

. c:\Framework-Scripts\common_functions.ps1
. c:\Framework-Scripts\secrets.ps1

[System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
if ($requestedNames -like "*,*") {
    $vmNameArray = $requestedNames.Split(',')
} else {
    $vmNameArray += $requestedNames
}

$suffix = $suffix -replace "_","-"

$commandString =
{
    param ( $DestRG,
            $DestSA,
            $location,
            $suffix,
            $command,
            $asRoot,
            $vm_name,
            $retryCount
            )

    . C:\Framework-Scripts\common_functions.ps1
    . C:\Framework-Scripts\secrets.ps1

    $logName = "C:\temp\transcripts\run_command_on_machines_in_group__scriptblock-" + $vm_name + "-" + (Get-Date -Format s).replace(":","-")
    Start-Transcript -path $logName -force >$null

    login_azure $DestRG $DestSA $location > $null

    Set-AzCurrentStorageAccount -ResourceGroupName $DestRG -StorageAccountName $DestSA > $null
    #
    #  Session stuff
    #
    $o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
    $cred = make_cred

    $suffix = $suffix.Replace(".vhd","")

    $password="$TEST_USER_ACCOUNT_PASS"

    if ($asRoot -ne $false) {
        $runCommand = "echo $password | sudo -S bash -c `'$command`'"
    } else {
        $runCommand = $command
    }

    $commandBLock=[scriptblock]::Create($runCommand)

    $result = ""
    [int]$timesTried = 0
    [bool]$success = $false
    while ($timesTried -lt $retryCount) {
        Write-verbose "Executing remote command on machine $vm_name, resource group $DestRG"
        $timesTried = $timesTried + 1

        $session = create_psrp_session $vm_name $DestRG $DestSA $location $cred $o
        if ($? -eq $true -and $session -ne $null) {
            $result = invoke-command -session $session -ScriptBlock $commandBLock -ArgumentList $command -ErrorAction SilentlyContinue
            $success = $true
            break
        } else {
            if ($session -ne $null) {
                Remove-PSSession -Session $session
            }
            if ($timesTried -lt $retryCount) {

                Write-Error "    Try $timesTried of $retryCount -- FAILED to establish PSRP connection to machine $vm_name."
            }
        }
        start-sleep -Seconds 10
    }

    Stop-Transcript > $null

    return $result
}

$commandBLock = [scriptblock]::Create($commandString)

get-job | Stop-Job
get-job | Remove-Job

foreach ($baseName in $vmNameArray) {
    $vm_name = $baseName
    $vm_name = $vm_name -replace ".vhd", ""
    $job_name = "run_command_" + $vm_name

    if ($vm_name -eq "") {
        continue
    }

    write-verbose "Executing command on machine $vm_name, resource group $destRG"

    start-job -Name $job_name -ScriptBlock $commandBLock -ArgumentList $DestRG, $DestSA, $location, $suffix, $command, $asRoot, $vm_name, $retryCount > $null
}

$jobFailed = $false
$jobBlocked = $false

Start-Sleep -Seconds 10
$blockedTime = 0

$allDone = $false
while ($allDone -eq $false) {
    $allDone = $true
    $numNeeded = $vmNameArray.Count
    $vmsFinished = 0
    $jobBlocked = $false

    foreach ($baseName in $vmNameArray) {
        $vm_name = $baseName
        $vm_name = $vm_name -replace ".vhd", ""
        $job_name = "run_command_" + $vm_name

        if ($vm_name -eq "") {
            continue
        }

        $job = Get-Job -Name $job_name
        $jobState = $job.State

        # write-verbose "    Job $job_name is in state $jobState"
        if ($jobState -eq "Running") {
            $allDone = $false
        } elseif ($jobState -eq "Failed") {
            Write-Error "**********************  JOB ON HOST MACHINE $vm_name HAS FAILED."
            $jobFailed = $true
            $vmsFinished = $vmsFinished + 1
            receive-job -name job_name -Keep
        } elseif ($jobState -eq "Blocked") {
            #
            #  Kind of hokey, but "blocked" in this case apparently includes time
            #  spent waiting for the remote machine to do something.  We need to add a timeout
            #  to the command, but for now let's just pass on the 'Blocked' thing until we see
            #  them for at least 5 minutes
            Write-verbose "**********************  HOST MACHINE $vm_name IS BLOCKED WAITING INPUT.  COMMAND WILL NEVER COMPLETE!!"

            if ($jobBlocked -eq $false) {
                $jobBlocked = $true
                $blockedTime = $blockedTime + 10

                if ($blockedTime -gt 600) {
                    Write-Error "**********************  JOB ON HOST MACHINE $vm_name HAS BEEN BLOCKED FOR 5 MINUTES.  ABORTING EXECUTION"

                    return 1
                }
            }
        } else {
            $vmsFinished = $vmsFinished + 1
        }
    }

    #
    #  Reset the blocked time so we don't accumulate
    if ($jobBlocked -eq $false) {
        $blockedTime = 0
    }

    if ($allDone -eq $false) {
        Start-Sleep -Seconds 10
    } elseif ($vmsFinished -eq $numNeeded) {
        break
    }
}

foreach ($baseName in $vmNameArray) {
    $vm_name = $baseName
    $vm_name = $vm_name -replace ".vhd", ""
    $job_name = "run_command_" + $vm_name

    if ($vm_name -eq "") {
        continue
    }

    Write-Host "Reply from machine $vm_name :" -ForegroundColor Green
    $output = (Get-Job $job_name | Receive-Job)
    foreach ($line in $output) {
        write-host "        "$line -ForegroundColor Magenta
    }
    write-host ""
}

if ($jobFailed -eq $true -or $jobBlocked -eq $true)
{
    exit 1
}

exit 0