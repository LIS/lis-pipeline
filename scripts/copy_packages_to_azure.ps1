param (
    [Parameter(Mandatory=$false)] [string] $destResourceGroup="smoke_output_resource_group",
    [Parameter(Mandatory=$false)] [string] $destAccountName="smoketestoutstorageacct",
    [Parameter(Mandatory=$false)] [string] $destContainer="last-build-packages",
    [Parameter(Mandatory=$false)] [string] $driveLetter="Z:\",
    [Parameter(Mandatory=$false)] [string] $location="westus"
)

$destResourceGroup=$destResourceGroup.Trim()
$destAccountName=$destAccountName.Trim()
$destContainer=$destContainer.Trim()
$driveLetter=$driveLetter.Trim()
$location=$location.Trim()
. "C:\Framework-Scripts\common_functions.ps1"


Write-Host "Copying Linux kernel build artifacts to the cloud..."
login_azure $destResourceGroup $destAccountName $location

$failure_point = "No failure"
$key=Get-AzureRmStorageAccountKey -ResourceGroupName $destResourceGroup -Name $destAccountName
if ($? -eq $false) {
    $failure_point="GetKey"
    ErrOut($failure_point)
}

New-AzureStorageContext -StorageAccountName $destAccountName -StorageAccountKey $key[0].Value
if ($? -eq $false) {
    $failure_point="NewContext"
    ErrOut($failure_point)
}

#
#  Copy the latest packages up to Azure
$packages=get-childitem -path $driveLetter
Remove-Item -Path C:\temp\file_list -Force

foreach ($package in $packages) {
    $package.name | out-file -Append C:\temp\file_list
}

#
#  Clear the working container
#
Get-AzureStorageBlob -Container $destContainer -blob * | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainer}
if ($? -eq $false) {
    $failure_point="ClearingContainers"
    ErrOut($failure_point)
}

#
#  Copy the kernel packages to Azure.
#
$drive = $driveLetter
Get-ChildItem $drive | Set-AzureStorageBlobContent -Container $destContainer -force
if ($? -eq $false) {
    $failure_point="CopyPackages"
    ErrOut($failure_point)
}

Write-Host "Copy complete."
exit 0


unction ErrOut([string] $failPoint) {
    #
    #  Not really sure what happened.  Better let a human have a look...
    #
    write-host "Copying packages to Azure has failed in operation $failure_point."
    exit 1
}