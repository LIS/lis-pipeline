#
#  Copies VHDs that have booted as expected to the test location where they will be prepped
#  for Azure automation
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smoketestoutstorageacct",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_output_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="generalized-images",

    [Parameter(Mandatory=$false)] [string] $destSA="smokebvt",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_bvts_resource_group",

    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string] $templateFile="bvt_template.xml",
    [Parameter(Mandatory=$false)] [string] $removeTag="-BORG",
    [Parameter(Mandatory=$false)] [string] $OverwriteVHDs="False",

    [Parameter(Mandatory=$true)] [string] $distro="Smoke-BVT",
    [Parameter(Mandatory=$true)] [string[]] $testCycles="BVT"
)

$sourceSA = $sourceSA.Trim()
$sourceRG = $sourceRG.Trim()
$sourceContainer = $sourceContainer.Trim()
$location = $location.Trim()
$templateFile = $templateFile.Trim()
$removeTag = $removeTag.Trim()
$OverwriteVHDs = $OverwriteVHDs.Trim()
$distro = $distro.Trim()
$testCycles = $testCycles.Trim()

. C:\Framework-Scripts\common_functions.ps1
. C:\Framework-Scripts\secrets.ps1

#
#  This is a required location
$removeTag = $removeTag -replace "_","-"
$destContainer="vhds"
$vmFlavor="no-flavor"

$copyblobs_array=@()
$copyblobs = {$copyblobs_array}.Invoke()
$copyblobs.Clear()

$successfulcopies_array=@()
$successfulCopies = {$successfulcopies_array}.Invoke()
$successfulCopies.Clear()

if ($OverwriteVHDs -ne "False") {
    $overwriteVHDs = $true
} else {
    $overwriteVHDs = $false
}

$logFileName = "C:\temp\transcripts\run_bvts_on_container-" + $sourceRG + "-" + $sourceSA + "-" + $sourceContainer + "-" + (Get-Date -Format s).replace(":","-")
Start-Transcript $logFileName

write-host "Overwrite flag is $overwriteVHDs"
get-job | Stop-Job
get-job | Remove-Job

set-location C:\azure-linux-automation
git pull

$blobFilter = '*.vhd'
if ($removeTag -ne "") {
    $blobFilter = '*' + $removeTag
}
Write-Host "Blob filter is $blobFilter"

$regionSuffix = ("---" + $location+ "-" + $VMFlavor.ToLower()) -replace " ","-"
$regionSuffix = $regionSuffix -replace "_","-"

$fullSuffix = $regionSuffix + "-Booted-and-Verified"

login_azure $sourceRG $sourceSA $location

Write-Host "Stopping all running machines..."  -ForegroundColor green
$runningVMs = Get-AzVM -ResourceGroupName $sourceRG
deallocate_machines_in_group $runningVMs $sourceRG $sourceSA $location

$sourceKey=Get-AzStorageAccountKey -ResourceGroupName $sourceRG -Name $sourceSA
$sourceContext=New-AzStorageContext -StorageAccountName $sourceSA -StorageAccountKey $sourceKey[0].Value

Set-AzCurrentStorageAccount -ResourceGroupName $sourceRG -StorageAccountName $sourceSA
$blobs=Get-AzStorageBlob -Container $sourceContainer -Blob $blobFilter

Write-Host "Deleting any existing storage account and recreating it."
$wasThere = $false
$currentLoc = $null
$existingAccount = $null
$existingAccount = Get-AzStorageAccount -ResourceGroupName $destRG -Name $destSA
if ($? -eq $true) {
    $wasThere = $true

    if ($existingAccount -ne $null) {
        $currentLoc = ($existingAccount.Location).ToString()
    }
}

if (($wasThere -eq $true) -and ($overwriteVHDs -eq $true)) {
    #
    #  Was the container there?
    Set-AzCurrentStorageAccount -ResourceGroupName $destRG -StorageAccountName $destSA

    $containerWasThere = Get-AzStorageContainer -Name $destContainer
    if ($? -eq $true -and $containerWasThere -ne $null) {
        Remove-AzStorageContainer -Name $destContainer -Force
    }
    # Remove-AzStorageAccount -ResourceGroupName $destRG -Name $destSA -Force
    # New-AzStorageAccount -ResourceGroupName $destRG -Name $destSA -Kind Storage -Location $location -SkuName Standard_LRS
} elseif (($wasThere -eq $true) -and ($OverwriteVHDs -eq $false)) {
    if ($currentLoc -ne $location) {
        Write-Error "The storage account exists, but it is in region $currentLoc, while the tests specify region $location.  Tests will exit."
        Stop-Transcript
        exit 1
    }
    Write-Host "Using existing storage account $destSA."
} else {
    Write-Host "Storage account did not exist.  Creating now..."
    New-AzStorageAccount -ResourceGroupName $destRG -Name $destSA -Kind Storage -Location $location -SkuName Standard_LRS
}
Set-AzCurrentStorageAccount -ResourceGroupName $destRG -StorageAccountName $destSA

Write-Host "Copying the test VMs packages to BVT resource group"
$destKey=Get-AzStorageAccountKey -ResourceGroupName $destRG -Name $destSA
$destContext=New-AzStorageContext -StorageAccountName $destSA -StorageAccountKey $destKey[0].Value

$existingContainer = Get-AzStorageContainer -name $destContainer
if ($? -eq $false -or $existingContainer -eq $null) {
    Write-Host "Making a new onwe..."
    New-AzStorageContainer -Name $destContainer -Permission Blob
    $existingBlobs = $null
} else {
    $existingBlobs=Get-AzStorageBlob -Container $destContainer
}

foreach ($oneblob in $blobs) {
    $fullName=$oneblob.Name

    if ($removeTag -ne "") {
        if ($removeTag -match ".*.vhd") {
            $targetName=$fullName.Replace($removeTag,$fullSuffix)
        } else {
            $targetName = $fullName -replace ".vhd",""
            $targetName = $targetName.Replace($removeTag,$fullSuffix)
        }
    } else {
        $targetName = $fullName -replace ".vhd",""
        $targetName = $targetName + $fullSuffix
    }

    if ($targetName.Length -gt 62) {
        Write-Warning "NOTE:  Image name $targetName is too long"
        $targetName = $targetName.substring(0, 62)
        Write-Warning "NOTE:  Image name is now $targetName"
        if ($targetName.EndsWith("-") -eq $true) {
            $targetName = $targetName -Replace ".$","X"
            Write-Warning "NOTE:  Image name is ended in an illegal character.  Image name is now $targetName"
        }
        Write-Warning "NOTE:  Image name $targetName was truncated to 62 characters"
    }
    $targetName = $targetName + ".vhd"

    $blobIsInDest = $false
    if ($existingBlobs.Name -contains $targetName) {
        $blobIsInDest = $true
    }

    $start_copy = $true
    if (($blobIsInDest -eq $true) -and ($overwriteVHDs -eq $true)) {
        Write-Host "There is an existing blob in the destination and the overwrite flag has been set.  The existing blob will be deleted."
        Remove-AzStorageBlob -Blob $targetName -Container $destContainer -Force
    } elseif ($blobIsInDest -eq $false) {
        Write-Host "This is a new blob."
    } else {
        Write-Host "There was an existing blob named $targetName, and the overwrite flag was not set.  Blob will not be copied."
        $start_copy = $false
    }

    if ($start_copy -eq $true) {
        Write-Host "Initiating job to copy VHD from $sourceSA/$sourceContainer/$fullName to $destSA/$destContainer/$targetName..." -ForegroundColor Yellow
        $blob = Start-AzStorageBlobCopy -SrcBlob $fullName -DestContainer $destContainer -SrcContainer $sourceContainer -DestBlob $targetName -Context $sourceContext -DestContext $destContext -Force
        if ($? -eq $true) {
            $copyblobs.Add($targetName)
        } else {
            Write-Host "Job to copy VHD $targetName failed to start.  Cannot continue"
            Stop-Transcript
            exit 1
        }
    }
}

if ($copyblobs.Count -gt 0) {
    Start-Sleep -Seconds 10
    Write-Host "All jobs have been launched.  Initial check is:" -ForegroundColor Yellow

    Set-AzCurrentStorageAccount -ResourceGroupName $destRG -StorageAccountName $destSA
    $stillCopying = $true
    while ($stillCopying -eq $true) {
        $stillCopying = $false
        $reset_copyblobs = $true

        Write-Host ""
        Write-Host "Checking copy status..."
        while ($reset_copyblobs -eq $true) {
            $reset_copyblobs = $false
            foreach ($blob in $copyblobs) {
                $status = Get-AzStorageBlobCopyState -Blob $blob -Container $destContainer -ErrorAction SilentlyContinue
                if ($? -eq $false) {
                    Write-Host "        Could not get copy state for job $blob.  Job may not have started." -ForegroundColor Yellow
                } elseif ($status.Status -eq "Pending") {
                    $bytesCopied = $status.BytesCopied
                    $bytesTotal = $status.TotalBytes
                    $pctComplete = ($bytesCopied / $bytesTotal) * 100
                    Write-Host "        Job $blob has copied $bytesCopied of $bytesTotal bytes ($pctComplete %)." -ForegroundColor green
                    $stillCopying = $true
                } else {
                    $exitStatus = $status.Status
                    if ($exitStatus -eq "Completed") {
                        Write-Host "   **** Job $blob has failed with state $exitStatus." -ForegroundColor Red
                    } else {
                        Write-Host "   **** Job $blob has completed successfully." -ForegroundColor Green
                        $successfulCopies.Add($blob)
                    }
                    $copyblobs.Remove($blob)
                    $reset_copyblobs = $true
                    break
                }
            }
        }

        if ($stillCopying -eq $true) {
            Write-Host ""
            Start-Sleep -Seconds 10
        } else {
            Write-Host ""
            Write-Host "All copy jobs have completed.  Rock on." -ForegroundColor green
        }
    }
}

# Set-AzCurrentStorageAccount -ResourceGroupName $destRG -StorageAccountName $destSA
# $blobs=Get-AzStorageBlob -Container $destContainer
Set-Location C:\azure-linux-automation
$launched_machines = 0

foreach ($oneblob in $successfulCopies) {
    $fullName=$oneblob.Name

    $configFileName="c:\temp\bvt_configs\bvt_exec_" + $fullName + ".xml"
    $jobName=$fullName + "_BVT_Runner"

    (Get-Content .\$templateFile).Replace("SMOKE_MACHINE_NAME_HERE",$fullName) | out-file $configFileName -Force
    (Get-Content $configFileName).Replace("STORAGE_ACCOUNT_NAME_HERE",$destSA) | out-file $configFileName -Force
    (Get-Content $configFileName).Replace("LOCATION_HERE",$location) | out-file $configFileName -Force

    #
    # Launch the automation
    write-host "Args are: $sourceName, $configFileName, $distro, $testCycles"
    Start-Job -Name $jobName -ScriptBlock { C:\Framework-Scripts\run_single_bvt.ps1 -sourceName $args[0] -configFileName $args[1] -distro $args[2] -testCycle $args[3]  } `
                                            -ArgumentList @($fullName),@($configFileName),@($distro),@($testCycles)
    if ($? -ne $true) {
        Write-Host "Error launching job $jobName for source $fullName.  BVT will not be run." -ForegroundColor Red
    } else {
        $launched_machines += 1
        $launchTime=date
        Write-Host "Job $jobName launched machine $fullName as BVT $launched_machines at $launchTime" -ForegroundColor Green
    }
}

#
#  Wait for completion...
$sleep_count=0
while ($completed_machines -lt $launched_machines) {

    $completed_machines = 0
    $failed_machines = 0
    $running_machines = 0
    $other_machines = 0

    $logThisOne=$false
    if ($sleep_count % 6 -eq 0) {
        $updateTime=date
        write-host "Update as of $updateTime.  There were $launched_machines started..."
        $logThisOne=$true
    }

    foreach ($oneblob in $blobs) {
        $fullName=$oneblob.Name

        $jobName=$fullName + "_BVT_Runner"

        $jobStatus=get-job -Name $jobName
        if ($? -eq $true) {
            $jobState = $jobStatus.State
            if ($jobState -eq "Failed")
            {
                $completed_machines += 1
                $failed_machines += 1
                if ($logThisOne -eq $true) {
                    Write-Host " >>>> BVT job $jobName exited with FAILED state!" -ForegroundColor red
                }
            }
            elseif ($jobState -eq "Completed")
            {
                $completed_machines += 1
                if ($logThisOne -eq $true) {
                    Write-Host "***** BVT job $jobName completed successfully." -ForegroundColor green
                }
            }
            elseif ($jobState -eq "Running")
            {
                $running_machines += 1
                if ($logThisOne -eq $true) {
                    Write-Host "      BVT job $jobName is still in progress." -ForegroundColor green
                }
            }
            else
            {
                $other_machines += 1
                Write-Host "????? BVT job $jobName is in state $jobState." -ForegroundColor Yellow
            }
        }
    }

    if ($logThisOne -eq $true) {
       write-host "$launched_machines BVT jobs were launched.  Of those: completed = $completed_machines, Running = $running_machines, Failed = $failed_machines, and unknown = $other_machines" -ForegroundColor green
    }

    $sleep_count += 1
    if ($completed_machines -lt $launched_machines) {
        Start-Sleep -Seconds 10
    } else {
        Write-Host "ALL BVTs have completed.  Checking results..."

        if ($failed_machines -gt 0) {
            Write-Host "There were $failed_machines failures out of $launched_machines attempts.  BVTs have failed." -ForegroundColor Red
            Stop-Transcript
            c:\framework-Scripts\clear_smoke_bvt_resource_groups
            exit 1
        } elseif ($completed_machines -eq $launched_machines) {
            Write-Host "All BVTs have passed! " -ForegroundColor Green
            Stop-Transcript
            c:\framework-Scripts\clear_smoke_bvt_resource_groups
            exit 0
        } else {
            write-host "$launched_machines BVT jobs were launched.  Of those: completed = $completed_machines, Running = $running_machines, Failed = $failed_machines, and unknown = $other_machines" -ForegroundColor Red
            Stop-Transcript
            c:\framework-Scripts\clear_smoke_bvt_resource_groups
            exit 1
        }
    }
}

