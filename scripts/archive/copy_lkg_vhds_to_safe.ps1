#
#  Copies VHDs that have booted as expected to the LKG drop location
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smokework",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="vhds-under-test",
    [Parameter(Mandatory=$false)] [string] $sourcePkgContainer="last-build-packages",

    [Parameter(Mandatory=$false)] [string] $destSA="smoketestoutstorageacct",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_output_resource_group",
    [Parameter(Mandatory=$false)] [string] $destContainer="last-known-good-vhds",
    [Parameter(Mandatory=$false)] [string] $destPkgContainer="last-known-good-packages",

    [Parameter(Mandatory=$false)] [string] $location="westus",
    [Parameter(Mandatory=$false)] [string] $excludePackages=$false,
    [Parameter(Mandatory=$false)] [string] $excludeVHDs=$false
)

$sourceSA = $sourceSA.Trim()
$sourceRG = $sourceRG.Trim()
$sourceContainer = $sourceContainer.Trim()
$sourcePkgContainer = $sourcePkgContainer.Trim()
$destSA = $destSA.Trim()
$destRG = $destRG.Trim()
$destContainer = $destContainer.Trim()
$destPkgContainer = $destPkgContainer.Trim()
$location = $location.Trim()
$excludePackages = $excludePackages.Trim()
$excludeVHDs = $excludeVHDs.Trim()

. "C:\Framework-Scripts\secrets.ps1"

$copyblobs_array=@()
$copyblobs = {$copyblobs_array}.Invoke()

write-verbose "Switch excludePackages is $excludePackages and switch excludeVHDs is $excludeVHDs"

write-verbose "Importing the context...." 
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx' > $null

write-verbose "Selecting the Azure subscription..." 
Select-AzureRmSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID" > $null
Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA > $null

$destKey=Get-AzureRmStorageAccountKey -ResourceGroupName $destRG -Name $destSA
$destContext=New-AzureStorageContext -StorageAccountName $destSA -StorageAccountKey $destKey[0].Value

$sourceKey=Get-AzureRmStorageAccountKey -ResourceGroupName $sourceRG -Name $sourceSA
$sourceContext=New-AzureStorageContext -StorageAccountName $sourceSA -StorageAccountKey $sourceKey[0].Value

#
#  Clear the working containers
#
write-verbose "Clearing any existing VHDs"
if ($excludeVHDs -eq $false) {
    Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA > $null
    Get-AzureStorageBlob -Container $destContainer -blob * | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainer}
    if ($? -eq $false) {
        $failure_point="ClearingContainers"
        ErrOut($failure_point)
    }
}


if ($excludePackages -eq $false) {
    write-verbose "Copying the build packages to LKG"
    Get-AzureStorageBlob -Container $destPkgContainer -blob * | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destPkgContainer}
    if ($? -eq $false) {
        $failure_point="ClearingContainers"
        ErrOut($failure_point)
    }

    #
    #  Now copy the packages
    Set-AzureRmCurrentStorageAccount –ResourceGroupName $sourceRG –StorageAccountName $sourceSA > $null

    write-verbose "Copying the VHDs to LKG"
    $blobs=get-AzureStorageBlob -Container $sourcePkgContainer -Blob *
    foreach ($oneblob in $blobs) {
        $sourceName=$oneblob.Name
        $targetName = $sourceName

        write-verbose "Initiating job to copy packages from $sourcePkgContainer from cache to working directory $destPkgContainer..." 
        $blob = Start-AzureStorageBlobCopy -SrcBlob $sourceName -SrcContainer $sourcePkgContainer  -DestContainer $destPkgContainer -DestBlob $targetName `
                                           -Context $sourceContext -DestContext $destContext
        if ($? -eq $true) {
            $copyblobs.Add($targetName)
        } else {
            write-verbose "Job to copy package $targetName failed to start.  Cannot continue"
            exit 1
        }
    }

    Start-Sleep -Seconds 5
    write-verbose "All jobs have been launched.  Initial check is:" 

    $stillCopying = $true
    while ($stillCopying -eq $true) {
        $stillCopying = $false
        $reset_copyblobs = $true

        write-verbose ""
        write-verbose "Checking copy status..."
        while ($reset_copyblobs -eq $true) {
            $reset_copyblobs = $false
            foreach ($blob in $copyblobs) {
                $status = Get-AzureStorageBlobCopyState -Blob $blob -Container $destContainer -ErrorAction SilentlyContinue
                if ($? -eq $false) {
                    write-verbose "        Could not get copy state for job $blob.  Job may not have started." 
                    $copyblobs.Remove($blob)
                    $reset_copyblobs = $true
                    break
                } elseif ($status.Status -eq "Pending") {
                    $bytesCopied = $status.BytesCopied
                    $bytesTotal = $status.TotalBytes
                    $pctComplete = ($bytesCopied / $bytesTotal) * 100
                    write-verbose "        Job $blob has copied $bytesCopied of $bytesTotal bytes (%$pctComplete)." 
                    $stillCopying = $true
                } else {
                    $exitStatus = $status.Status
                    if ($exitStatus -eq "Completed") {
                        write-verbose "   **** Job $blob has failed with state $exitStatus." 
                    } else {
                        write-verbose "   **** Job $blob has completed successfully." 
                    }
                    $copyblobs.Remove($blob)
                    $reset_copyblobs = $true
                    break
                }
            }
        }

        if ($stillCopying -eq $true) {
            write-verbose ""
            Start-Sleep -Seconds 10
        } else {
            write-verbose ""
            write-verbose "All copy jobs have completed.  Rock on." 
        }
    }

}

if ($excludeVHDs -eq $true) {
    exit 0
}

write-verbose "Launching jobs to copy individual machines..." 

Set-AzureRmCurrentStorageAccount –ResourceGroupName $sourceRG –StorageAccountName $sourceSA > $null
$sourceContainer

get-AzureStorageBlob -Container $sourceContainer -Blob "*-BORG.vhd"
$blobs=get-AzureStorageBlob -Container $sourceContainer -Blob "*-BORG.vhd"
foreach ($oneblob in $blobs) {
    $sourceName=$oneblob.Name
    $targetName = $sourceName -replace "-BORG.vhd", "-Booted-and-Verified.vhd"

    write-verbose "Initiating job to copy VHD $targetName from final build to output cache directory..." 
    Start-AzureStorageBlobCopy -SrcBlob $sourceName -DestContainer $destContainer -SrcContainer $sourceContainer -DestBlob $targetName -Context $sourceContext -DestContext $destContext -Force > $null
    if ($? -eq $true) {
        $copyblobs.Add($targetName)
    } else {
        Write-error "Job to copy VHD $targetName failed to start.  Cannot continue" 
        exit 1
    }
}

Start-Sleep -Seconds 5
write-verbose "All jobs have been launched.  Initial check is:" 

Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA  > $null
$stillCopying = $true
while ($stillCopying -eq $true) {
    $stillCopying = $false
    $reset_copyblobs = $true

    write-verbose ""
    write-verbose "Checking copy status..."
    while ($reset_copyblobs -eq $true) {
        $reset_copyblobs = $false
        foreach ($blob in $copyblobs) {
            $status = Get-AzureStorageBlobCopyState -Blob $blob -Container $destContainer -ErrorAction SilentlyContinue
            if ($? -eq $false) {
                write-verbose "        Could not get copy state for job $blob.  Job may not have started." 
                $copyblobs.Remove($blob)
                $reset_copyblobs = $true
                break
            } elseif ($status.Status -eq "Pending") {
                $bytesCopied = $status.BytesCopied
                $bytesTotal = $status.TotalBytes
                $pctComplete = ($bytesCopied / $bytesTotal) * 100
                write-verbose "        Job $blob has copied $bytesCopied of $bytesTotal bytes (%$pctComplete)." 
                $stillCopying = $true
            } else {
                $exitStatus = $status.Status
                if ($exitStatus -eq "Completed") {
                    write-error "   **** Job $blob has failed with state $exitStatus." 
                } else {
                    write-verbose "   **** Job $blob has completed successfully." 
                }
                $copyblobs.Remove($blob)
                $reset_copyblobs = $true
                break
            }
        }
    }

    if ($stillCopying -eq $true) {
        write-verbose ""
        Start-Sleep -Seconds 10
    } else {
        write-verbose ""
        write-verbose "All copy jobs have completed.  Rock on." 
    }
}

write-verbose "All done!"
exit 0
