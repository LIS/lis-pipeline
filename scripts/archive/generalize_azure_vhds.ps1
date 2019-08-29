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

    [Parameter(Mandatory=$false)] [string] $destSA="smokework",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $destContainer="generalized-images",


    [Parameter(Mandatory=$false)] [string] $requestedNames="",
    [Parameter(Mandatory=$false)] [string] $generalizeAll="True",

    [Parameter(Mandatory=$false)] [string] $location="",

    [Parameter(Mandatory=$false)] [string] $suffix="-Runonce-Primed.vhd"
)

$sourceSA = $sourceSA.Trim()
$sourceRG = $sourceRG.Trim()
$sourceContainer = $sourceContainer.Trim()
$destSA = $destSA.Trim()
$destRG = $destRG.Trim()
$destContainer = $destContainer.Trim()
$suffix = $suffix.Trim()

$suffix = $suffix -replace "_","-"

. C:\Framework-Scripts\common_functions.ps1
. C:\Framework-Scripts\secrets.ps1

$logName = "C:\temp\transcripts\generalize_vhds-" + (Get-Date -Format s).replace(":","-")
Start-Transcript -path $logName -force

$overallTimer = [Diagnostics.Stopwatch]::StartNew()

$commandTimer = [Diagnostics.Stopwatch]::StartNew()

[System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
if ($requestedNames.ToLower() -eq "unset") {
    $requestedNames = ""
}

if ($requestedNames -like "*,*") {
    $vmNameArray = $requestedNames.Split(',')
} elseif ($requestedNames -ne "") {
    $vmNameArray = $requestedNames
} else {
    $vmNameArray.clear()
}

[System.Collections.ArrayList]$base_names_array
$machineBaseNames = {$base_names_array}.Invoke()
$machineBaseNames.Clear()

[System.Collections.ArrayList]$full_names_array
$machineFullNames = {$full_names_array}.Invoke()
$machineFullNames.Clear()

login_azure $sourceRG $sourceSA $location
Set-AzCurrentStorageAccount -ResourceGroupName $sourceRG -StorageAccountName $sourceSA

$vmName = $vmNameArray[0]
if ($generalizeAll -eq $false -and $vmNameArray.Count -eq 0) {
    Write-Host "Must specify either a list of VMs in RequestedNames, or use generalizeAll.  Unable to process this request."
    Stop-Transcript
    exit 1
} else {
    $requestedNames = ""
    $runningVMs = Get-AzVM -ResourceGroupName $sourceRG

    if ($generalizeAll -eq $true) {
        Write-Host "Generalizing all running machines..."
        foreach ($vm in $runningVMs) {
            $vm_name=$vm.Name
            $requestedNames = $requestedNames + $vm_name + ","
            $machineBaseNames += $vm_name
            $machineFullNames += $vm_name
        }
    } else {
        write-host "Generalizing only specific machines"
        foreach ($vm in $runningVMs) {
            $vm_name=$vm.Name
            foreach ($name in $requestedNames) {
                if ($vm_name.contains($name)) {
                    Write-Host "Including VM $vm_name"
                    $requestedNames = $requestedNames + $vm_name + ","
                    $machineBaseNames += $name
                    $machineFullNames += $vm_name
                    break
                }
            }
        }
    }

    $requestedNames = $requestedNames -replace ".$"
    $suffix = ""
}

$systemContainer = "system"

Remove-AzStorageContainer -Name $systemContainer -Force

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed to set up"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()
Write-Host "Making sure we're up to date"

C:\Framework-Scripts\run_command_on_machines_in_group.ps1 -requestedNames $requestedNames -destSA $sourceSA -destRG $sourceRG `
                                                          -suffix $suffix -asRoot "True" -location $location -command "cd /HIPPEE/Framework-Scripts; git pull"
Write-Host "Replacing cloud-init..."
C:\Framework-Scripts\run_command_on_machines_in_group.ps1 -requestedNames $requestedNames -destSA $sourceSA -destRG $sourceRG `
                                                          -suffix $suffix -asRoot "True" -location $location -command "/bin/mv /usr/bin/cloud-init.DO_NOT_RUN_THIS /usr/bin/cloud-init"

Write-Host "Deprovisioning..."
C:\Framework-Scripts\run_command_on_machines_in_group.ps1 -requestedNames $requestedNames -destSA $sourceSA -destRG $sourceRG `
                                                          -suffix $suffix -asRoot "True" -location $location -command "waagent -deprovision -force"
 if ($? -eq $false) {
    Write-Host "FAILED to deprovision machines" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Write-Host "And stopping..."
C:\Framework-Scripts\run_command_on_machines_in_group.ps1 -requestedNames $requestedNames -destSA $sourceSA -destRG $sourceRG `
                                                          -suffix $suffix -asRoot "True" -location $location -command "bash -c shutdown"
if ($? -eq $false) {
    Write-Host "FAILED to stop machines" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed generalize and stop the machines"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

$scriptBlockText = {

    param (
        [string] $machine_name,
        [string] $sourceRG,
        [string] $sourceSA,
        [string] $sourceContainer,
        [string] $location
    )

    . C:\Framework-Scripts\common_functions.ps1
    . C:\Framework-Scripts\secrets.ps1

    $commandTimer = [Diagnostics.Stopwatch]::StartNew()

    login_azure $sourceRG $sourceSA $location
    Set-AzCurrentStorageAccount -ResourceGroupName $rg -StorageAccountName $s
    #
    #  This might not be the best way, but I only have 23 characters here, so we'll go with what the user entered
    $bar=$machine_name.Replace("---","{")
    $vhdPrefix = $bar.split("{")[0]
    if ($vhdPrefix.Length -gt 22) {
        $vhdPrefix = $vhdPrefix.substring(0,23)
    }
    Write-Host "Set the VHD Prefix to " $vhdPrefix

    $logName = "C:\temp\transcripts\generalize_vhds_scriptblock-" + $machine_name + "-" + (Get-Date -Format s).replace(":","-")
    Start-Transcript -path $logName -force

    write-host "Stopping machine $machine_name for VHD generalization"
    Stop-AzVM -Name $machine_name -ResourceGroupName $sourceRG -Force

    write-host "Settng machine $machine_name to Generalized"
    Set-AzVM -Name $machine_name -ResourceGroupName $sourceRG -Generalized

    write-host "Saving image for machnine $machine_name to container $sourceContainer in RG $sourceRG"
    Save-AzVMImage -VMName $machine_name -ResourceGroupName $sourceRG -DestinationContainerName $sourceContainer -VHDNamePrefix $vhdPrefix

    write-host "Deleting machine $machine_name"
    Remove-AzVM -Name $machine_name -ResourceGroupName $sourceRG -Force

    Write-Host "Generalization of machine $machine_name complete."

    $commandTimer.Stop()
    $elapsed = $commandTimer.Elapsed
    Write-Host "It required $elapsed deprovision in the scriptblock"

    Stop-Transcript
}

$scriptBlock = [scriptblock]::Create($scriptBlockText)

[int]$nameIndex = 0
foreach ($vm_name in $machineBaseNames) {
    $machine_name = $machineFullNames[$nameIndex]
    $nameIndex = $nameIndex + 1
    $jobName = "generalize_" + $machine_name

    Write-Host "Launching job to save the off-line state of machine $vm_name ($machine_name)"

    Start-Job -Name $jobName -ScriptBlock $scriptBlock -ArgumentList $machine_name, $sourceRG, $sourceSA, $sourceContainer, $location
}

start-sleep -seconds 10

$allDone = $false
while ($allDone -eq $false) {
    $allDone = $true
    $numNeeded = $vmNameArray.Count
    $vmsFinished = 0

    Write-Host "Checking status of deprovisioning jobs..." -ForegroundColor Yellow
    [int]$nameIndex = 0
    foreach ($vm_name in $machineBaseNames) {
        $machine_name = $machineFullNames[$nameIndex]
        $nameIndex = $nameIndex + 1
        $jobName = "generalize_" + $machine_name
        $job = Get-Job -Name $jobName
        $jobState = $job.State

        write-host "    Job $jobName is in state $jobState" -ForegroundColor Yellow
        if ($jobState -eq "Running") {
            write-verbose "job $jobName is still running..."
            $allDone = $false
        } elseif ($jobState -eq "Failed") {
            write-host "**********************  JOB ON HOST MACHINE $jobName HAS FAILED TO START." -ForegroundColor Red
            # $jobFailed = $true
            $vmsFinished = $vmsFinished + 1
            get-job -Name $jobName | receive-job
            $Failed = $true
        } elseif ($jobState -eq "Blocked") {
            write-host "**********************  HOST MACHINE $jobName IS BLOCKED WAITING INPUT.  COMMAND WILL NEVER COMPLETE!!" -ForegroundColor Red
            # $jobBlocked = $true
            $vmsFinished = $vmsFinished + 1
            get-job -Name $jobName | receive-job
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
    Write-Host "Machine generalization failed.  Please check the logs." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed finish the generalization process"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

#
#  The generalization process, if successful, placed the VHDs in a location below the current
#  storage container, with the prefix we gave it but some random junk on the back.  We will copy those
#  VHDs, and their associated JSON files, to the output storage container, renaming them
# to <user supplied>---no_loc-no_flav-generalized.vhd

Write-Host "Copying generalized VHDs in container $systemContainer (from $sourceContainer) from region $location."-ForegroundColor Magenta

$destKey=Get-AzStorageAccountKey -ResourceGroupName $destRG -Name $destSA
$destContext=New-AzStorageContext -StorageAccountName $destSA -StorageAccountKey $destKey[0].Value

$sourceKey=Get-AzStorageAccountKey -ResourceGroupName $sourceRG -Name $sourceSA
$sourceContext=New-AzStorageContext -StorageAccountName $sourceSA -StorageAccountKey $sourceKey[0].Value

$copyBlobs = @()

Set-AzCurrentStorageAccount -ResourceGroupName $sourceRG -StorageAccountName $sourceSA
Write-Host "Copying generalized VHDs in container $systemContainer from region $location to $destRG / $destSA / $destContainer"
if ($generalizeAll -eq $true) {
    $blobs=Get-AzStorageBlob -Container $systemContainer  -Blob "*.vhd"
    $blobCount = $blobs.Count
    Write-Host "Copying generalized VHDs in container / $sourceRG / $sourceSA / $systemContainer from region $location.  There will be $blobCount VHDs :"-ForegroundColor Magenta
    foreach ($blob in $blobs) {
        $copyblobs += $blob
        $blobName = $blob.Name
        write-host "                       $blobName" -ForegroundColor Magenta
    }
} else {
    $blobs=Get-AzStorageBlob -Container $systemContainer -Blob "*.vhd"
    foreach ($blob in $blobs) {
        write-host "Blobs name :" $blob.Name
    }

    foreach ($vmName in $vmNameArray) {
        Write-Host "Looking for a match of $vmName in the blobs"
        $foundIt = $false
        foreach ($blob in $blobs) {
            $blobName = $blob.Name
            $matchName = "*" + $vmName + "*"
            Write-Host "Looking for a match of $matchName in blob name $blobName"
            if ($blobName -match $matchName)  {
                $copyblobs += $blob
                write-host "Added blob $blobName"
                $foundIt = $true
            }
        }

        if ($foundIt -eq $false) {
            Write-Host " ***** ??? Could not find source blob $theName in container $systemContainer.  This request is skipped" -ForegroundColor Red
        }
    }
}

Set-AzCurrentStorageAccount -ResourceGroupName $destRG -StorageAccountName $destSA

Get-AzStorageBlob -Container $destContainer -Prefix "*"
if ($? -eq $false) {
    Write-Host "creating the generalization destination container" -ForegroundColor Yellow
    New-AzStorageContainer -Name $destContainer -Permission Blob
}

foreach ($blob in $copyblobs) {
    $blobName = $blob.Name
    $longName=($blobName -split "$sourceContainer/")[1]
    $baseName=($longName -split "-osdisk")[0]
    $targetName = $baseName + "-generalized.vhd"

    Write-Host "Initiating job to copy VHD $blobName from $sourceRG and $systemContainer to $targetName in $destRG and $destSA, container $destContainer" -ForegroundColor Yellow
    # if ($overwriteVHDs -eq $true) {
        Write-Host "Clearing destination container of all VHDs with prefix $baseName"
        Get-AzStorageBlob -Container $destContainer -Blob "$baseName*" | ForEach-Object {Remove-AzStorageBlob -Blob $_.Name -Container $destContainer }

        $blob = Start-AzStorageBlobCopy -SrcBlob $blobName -DestContainer $destContainer -SrcContainer $systemContainer -DestBlob $targetName -Context $sourceContext -DestContext $destContext -Force
    # } else {
    #     $blob = Start-AzStorageBlobCopy -SrcBlob $blobName -DestContainer $destContainer -SrcContainer $systemContainer -DestBlob $targetName -Context $sourceContext -DestContext $destContext
    # }

    if ($? -eq $false) {
        Write-Host "Job to copy VHD $targetName failed to start.  Cannot continue"
        Stop-Transcript
        exit 1
    }
}

Start-Sleep -Seconds 5
Write-Host "All jobs have been launched.  Initial check is:" -ForegroundColor Yellow

$stillCopying = $true
while ($stillCopying -eq $true) {
    $stillCopying = $false

    write-host ""
    write-host "Checking blob copy status..." -ForegroundColor yellow

    foreach ($blob in $copyblobs) {
        $blobName = $blob.Name
        $longName=($blobName -split "$sourceContainer/")[1]
        $baseName=($longName -split "-osdisk")[0]
        $targetName = $baseName + "-generalized.vhd"

        $copyStatus = Get-AzStorageBlobCopyState -Blob $targetName -Container $destContainer -ErrorAction SilentlyContinue
        $status = $copyStatus.Status
        if ($? -eq $false) {
            Write-Host "        Could not get copy state for job $targetName.  Job may not have started." -ForegroundColor Yellow
            break
        } elseif ($status -eq "Pending") {
            $bytesCopied = $copyStatus.BytesCopied
            $bytesTotal = $copyStatus.TotalBytes
            if ($bytesTotal -le 0) {
                Write-Host "        Job $targetName not started copying yet." -ForegroundColor green
            } else {
                $pctComplete = ($bytesCopied / $bytesTotal) * 100
                Write-Host "        Job $targetName has copied $bytesCopied of $bytesTotal bytes ($pctComplete %)." -ForegroundColor green
            }
            $stillCopying = $true
        } else {
            if ($status -eq "Success") {
                Write-Host "   **** Job $targetName has completed successfully." -ForegroundColor Green
            } else {
                Write-Host "   **** Job $targetName has failed with state $Status." -ForegroundColor Red
            }
        }
    }

    if ($stillCopying -eq $true) {
        Start-Sleep -Seconds 10
    } else {
        Write-Host "All copy jobs have completed.  Your generalized VHDs are in $destRG / $destSA / $destContainer.  It could be groovy." -ForegroundColor Green
    }
}

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed finish the generalization"

$overallTimer.Stop()
$elapsed = $overallTimer.Elapsed
Write-Host "It required $elapsed run this script"
Stop-Transcript

exit 0