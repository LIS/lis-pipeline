#
#  Copies user VHDs it finds for VMs in the reference resource group into the 'clean-vhds'
#  storage container.  The target blobs will have the name of the VM, as a .vhd
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smokesrc",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="clean-vhds",
    [Parameter(Mandatory=$false)] [string] $sourceExtension="Smoke-1",


    [Parameter(Mandatory=$false)] [string] $destSA="smokesrc",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $destContainer="safe-templates",
    [Parameter(Mandatory=$false)] [string] $destExtension="Smoke-1",

    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string[]] $vmNamesIn,

    [Parameter(Mandatory=$false)] [string] $makeDronesFromAll=$false,
    [Parameter(Mandatory=$false)] [string] $clearDestContainer=$false,
    [Parameter(Mandatory=$false)] [string] $overwriteVHDs=$false
)

$sourceSA = $sourceSA.Trim()
$sourceRG = $sourceRG.Trim()
$sourceContainer = $sourceContainer.Trim()
$destSA = $destSA.Trim()
$destRG = $destRG.Trim()
$destContainer = $destContainer.Trim()
$location = $location.Trim()
$sourceExtension = $sourceExtension.Trim()
$destExtension = $destExtension.Trim()

$logName= "C:\temp\transcripts\copy_single_image_container_to_container-" + $VMNamesIn[0] + "-" + (get-date -format s).replace(":","-")
Start-Transcript -path $logName -Force

. "C:\Framework-Scripts\common_functions.ps1"

Write-Host "Switch overwriteVHDs is $overwriteVHDs"

$copyblobs_array=@()
$copyblobs = {$copyblobs_array}.Invoke()
$copyblobs.Clear()

$copyJobs_array=@()
$copyJobs = {$copyJobs_array}.Invoke()
$copyJobs.Clear()

$vmNames_array=@()
$vmNames = {$vmNames_array}.Invoke()
$vmNames.Clear()
if ($vmNamesIn -like "*,*") {
    $vmNames = $vmNamesIn.Split(',')
} else {
    $vmNames = $vmNamesIn
}

login_azure $destRG $destSA $location

Write-Host "Stopping all running machines..."  -ForegroundColor green
get-job | Stop-Job
get-job | remove-job
$same_rg=$false
if ($sourceRG -eq $destRG) {
    $same_rg = $true
}

$runningVMs_Source=@()
$runningVMsSource = {$runningVMs_Source}.Invoke()
$runningVMsSource.Clear()

$runningVMs_Dest=@()
$runningVMsDest = {$runningVMs_Dest}.Invoke()
$runningVMsDest.Clear()

if ($makeDronesFromAll -eq $false) {
    #
    #  Build the list of VMs to stop/delete
    foreach ($vmName in $vmNames) {
        if ($same_rg -eq $false) {
            $runningVMsSource += (Get-AzVM -ResourceGroupName $sourceRG -status | Where-Object -Property Name -Like "$vmName*" | where-object -Property PowerState -eq -value "VM running")
        }

        $runningVMsDest += (Get-AzVM -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*")
    }
} else {
    if ($same_rg -eq $false) {
        $runningVMsSource = (Get-AzVM -ResourceGroupName $sourceRG -status | where-object -Property PowerState -eq -value "VM running")
    }
    $runningVMsDest = (Get-AzVM -ResourceGroupName $destRG -status)
}

if ($same_rg -eq $false) {
    deallocate_machines_in_group $runningVMsSource $sourceRG $sourceSA $location
}

deallocate_machines_in_group $runningVMsDest $destRG $destSA $location

Write-Host "Launching jobs to copy individual machines..." -ForegroundColor Yellow

$destKey=Get-AzStorageAccountKey -ResourceGroupName $destRG -Name $destSA
$destContext=New-AzStorageContext -StorageAccountName $destSA -StorageAccountKey $destKey[0].Value

$sourceKey=Get-AzStorageAccountKey -ResourceGroupName $sourceRG -Name $sourceSA
$sourceContext=New-AzStorageContext -StorageAccountName $sourceSA -StorageAccountKey $sourceKey[0].Value

Set-AzCurrentStorageAccount -ResourceGroupName $sourceRG -StorageAccountName $sourceSA
if ($makeDronesFromAll -eq $true) {
    $blobs=Get-AzStorageBlob -Container $sourceContainer -Blob "*$sourceExtension"
    $blobCount = $blobs.Count
    Write-Host "Making drones of all VHDs in container $sourceContainer from region $location, with extenstion $sourceExtension.  There will be $blobCount VHDs:"-ForegroundColor Magenta
    $vmNames.Clear()
    foreach ($blob in $blobs) {
        $copyblobs += $blob
        $blobName = $blob.Name
        write-host "                       $blobName" -ForegroundColor Magenta
        $vmNames.Add($blobName)
    }
} else {
    $blobs=Get-AzStorageBlob -Container $sourceContainer -Blob "*.vhd"
    foreach ($vmName in $vmNames) {
        $foundIt = $false
        foreach ($blob in $blobs) {
            $blobName = $blob.Name
            $matchName = "*" + $vmName + "*"
            write-host "Looking for match of $matchName in $blobName"
            if ( $blobName -like $matchName)  {
                $foundIt = $true
                break
            }
        }

        if ($foundIt -eq $true) {
            write-host "Added blob $theName (" $blob.Name ")"
            $copyblobs += $blob
        } else {
            Write-Host " ***** ??? Could not find source blob $theName in container $sourceContainer.  This request is skipped" -ForegroundColor Red
        }
    }
}

Set-AzCurrentStorageAccount -ResourceGroupName $destRG -StorageAccountName $destSA
if ($clearDestContainer -eq $true) {
    Write-Host "Clearing destination container of all jobs with extension $destExtension"
    Get-AzStorageBlob -Container $destContainer -Blob "*$destExtension" | ForEach-Object {Remove-AzStorageBlob -Blob $_.Name -Container $destContainer }
}

[int] $index = 0
foreach ($vmName in $vmNames) {
    $sourceName = $vmName + $sourceExtension
    $targetName = $vmName + $destExtension
    $extNoVHD = $destExtension -replace ".vhd",""
    $targetName = $vmName + $extNoVHD
    if ($targetName.Length -gt 62) {
        Write-Warning "NOTE:  Image name $targetName is too long"
        $targetName = $targetName.substring(0, 62)
        Write-Warning "NOTE:  Image name is now $targetName"
        if ($targetName.EndsWith("-") -eq $true) {
            $targetName = $targetName -Replace ".$","X"
            Write-Warning "NOTE:  Image name is ended in an illegal character.  Image name is now $targetName"
        }
        Write-Warning "NOTE:  Image name $imageName was truncated to 62 characters"
    }
    $targetName = $targetName + ".vhd"

    $sourceBlob = $copyBlobs[$index]
    $sourceBlobName = $sourceBlob.Name

    $index = $index + 1

    Write-Host "Copying source blob $sourceBlobName"

    Write-Host "Initiating job to copy VHD $sourceName from $sourceRG and $sourceContainer to $targetName in $destRG and $destSA, container $destContainer" -ForegroundColor Yellow
    if ($overwriteVHDs -eq $true) {
        $blob = Start-AzStorageBlobCopy -SrcBlob $sourceBlob.Name -DestContainer $destContainer -SrcContainer $sourceContainer -DestBlob $targetName -Context $sourceContext -DestContext $destContext -Force
    } else {
        $blob = Start-AzStorageBlobCopy -SrcBlob $sourceBlob.Name -DestContainer $destContainer -SrcContainer $sourceContainer -DestBlob $targetName -Context $sourceContext -DestContext $destContext
    }

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

    foreach ($vmName in $vmNames) {
        $sourceName = $vmName + $sourceExtension

        $extNoVHD = $destExtension -replace ".vhd",""
        $targetName = $vmName + $extNoVHD
        if ($targetName.Length -gt 62) {
            Write-Warning "NOTE:  Image name $targetName is too long"
            $targetName = $targetName.substring(0, 62)
            Write-Warning "NOTE:  Image name is now $targetName"
            if ($targetName.EndsWith("-") -eq $true) {
                $targetName = $targetName -Replace ".$","X"
                Write-Warning "NOTE:  Image name is ended in an illegal character.  Image name is now $targetName"
            }
            $targetName = $targetName + ".vhd"
            Write-Warning "NOTE:  Image name $imageName was truncated to 62 characters"
        }

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
        Write-Host "All copy jobs have completed.  Rock on." -ForegroundColor Green
    }
}
# Stop-Transcript

exit 0
