#
#  Copies VHDs that have booted as expected to the test location where they will be prepped
#  for Azure automation
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smokework",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="vhds-under-test",
    
    [Parameter(Mandatory=$false)] [string] $suffix="-Runonce-Primed.vhd",

    [Parameter(Mandatory=$false)] [string] $command="unset",
    [Parameter(Mandatory=$false)] [string] $asRoot="False",
    [Parameter(Mandatory=$true) ] [string] $StartMachines="False",

    [Parameter(Mandatory=$false)] [string] $network="smokeVNet",
    [Parameter(Mandatory=$false)] [string] $subnet="SmokeSubnet-1",
    [Parameter(Mandatory=$false)] [string] $NSG="SmokeNSG",
    [Parameter(Mandatory=$false)] [string] $location="westus"
)

$sourceSA = $sourceSA.Trim()
$sourceRG = $sourceRG.Trim()
$sourceContainer = $sourceContainer.Trim()
$suffix = $suffix.Trim()
$command = $command.Trim()
$asRoot = $asRoot.Trim()
$StartMachines = $StartMachines.Trim()
$network = $network.Trim()
$subnet = $subnet.Trim()
$NSG = $NSG.Trim()
$location = $location.Trim()

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

login_azure $sourceRG $sourceSA $location

$blobs = Get-AzureStorageBlob -Container $sourceContainer

# Write-Host "Executing command on all running machines in resource group $sourceRG..."  -ForegroundColor green

$failed = $false

$comandScript = {
    param (
        $blobName,
        $startMachines,
        $sourceRG,
        $sourceSA,
        $sourceContainer,
        $network,
        $subnet,
        $NSG,
        $location)

    $logName = "C:\temp\transcripts\run_command_on_container_scriptblock-" +$blobName + "-" + (Get-Date -Format s).replace(":","-")
    Start-Transcript -path $logName -force

    . C:\Framework-Scripts\common_functions.ps1
    . C:\Framework-Scripts\secrets.ps1

    login_azure $sourceRG $sourceSA $location
     
    $runningVMs = Get-AzureRmVm -ResourceGroupName $sourceRG
    if ($runningVMs.Name -contains $blobName) {
        write-host "VM $blobName is running"
    } else {
        Write-Host "VM $blobName is not running."

        if ($StartMachines -ne $false) {
            Write-Host "Starting VM for VHD $blobName..."
            .\launch_single_azure_vm.ps1 -vmName $blobName -resourceGroup $sourceRG -storageAccount $sourceSA `
                                         -containerName $sourceContainer -network $network -subnet $subnet `
                                         -NSG $NSG -Location $location -useInitialPW "No"
        } else {
            Write-Host "StartMachine was not set.  VM $blobName will not be started or used."
            $failed = $true
        }
    }

    Stop-Transcript

    if ($failed -eq $true) {
        exit 1
    }

    exit 0
}

$scriptBlock = [scriptblock]::Create($comandScript)

[System.Collections.ArrayList]$copyblobs_array
$copyblobs = {$copyblobs_array}.Invoke()
$copyblobs.clear()

foreach ($blob in $blobs) {
    $blobName = ($blob.Name).replace(".vhd","")
    $copyblobs += $blobName

    $vmJobName = "start_" + $blobName

    Start-Job -Name $vmJobName -ScriptBlock $scriptBlock -ArgumentList $blobName, $startMachines, $sourceRG, $sourceSA, $sourceContainer, `                                                                           $network, $subnet, $NSG
}

$allDone = $false
while ($allDone -eq $false) {
    $allDone = $true
    $numNeeded = $vmNameArray.Count
    $vmsFinished = 0

    foreach ($blob in $blobs) {
        $blobName = ($blob.Name).replace(".vhd","")

        $vmJobName = "start_" + $blobName
        $job = Get-Job -Name $vmJobName
        $jobState = $job.State

        # write-host "    Job $job_name is in state $jobState" -ForegroundColor Yellow
        if ($jobState -eq "Running") {
            $allDone = $false
        } elseif ($jobState -eq "Failed") {
            write-host "**********************  JOB ON HOST MACHINE $vmJobName HAS FAILED TO START." -ForegroundColor Red
            # $jobFailed = $true
            $vmsFinished = $vmsFinished + 1
            $Failed = $true
        } elseif ($jobState -eq "Blocked") {
            write-host "**********************  HOST MACHINE $vmJobName IS BLOCKED WAITING INPUT.  COMMAND WILL NEVER COMPLETE!!" -ForegroundColor Red
            # $jobBlocked = $true
            $vmsFinished = $vmsFinished + 1
            $Failed = $true
        } else {
            $vmsFinished = $vmsFinished + 1
        }
    }

    if ($allDone -eq $false) {
        Start-Sleep -Seconds 10
    } elseif ($vmsFinished -eq $numNeeded) {
        break
    }
}

if ($Failed -eq $true) {
    Write-Host "Remote command execution failed because we could not !" -ForegroundColor Red
    exit 1
} 

$name_list = ""
foreach ($blob in $blobs) {
    $blobName = ($blob.Name).replace(".vhd","")
    $name_list = $name_list + $blobName + ","
}

$name_list = $name_list -replace ".$"
C:\Framework-Scripts\run_command_on_machines_in_group.ps1 -requestedNames $name_list -destSA $sourceSA -destRG $sourceRG -suffix $suffix -command $command -asRoot $asRoot
