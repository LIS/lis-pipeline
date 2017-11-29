
param (
    [Parameter(Mandatory=$true)] [string] $g,
    [Parameter(Mandatory=$true)] [string] $u,
    [Parameter(Mandatory=$true)] [string] $n,
    [Parameter(Mandatory=$true)] [string] $j
)

. "C:\Framework-Scripts\secrets.ps1"

$logFileName="c:/temp/transcripts/download_single_vm-" + $j + ".log"
$localFileName=$n

Start-Transcript -Path $logFileName -Force

remove-item -path $logFileName -Force
Write-Host "DownloadSingleVM called for RG $g, URI $u, path $n"

$nm="azuresmokestoragesccount"

Write-Host "Importing the context...." | out-file $logFileName
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

Write-Host "Selecting the Azure subscription..." | out-file -append $logFileName
Select-AzureRmSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $g –StorageAccountName $nm 

Write-Host "Attempting to save the VM..."
Save-AzureRmVhd -Verbose -ResourceGroupName $g -SourceUri $u -LocalFilePath $localFileName -overwrite -NumberOfThreads 10
Write-Host "Attempt complete..."
       
Stop-Transcript