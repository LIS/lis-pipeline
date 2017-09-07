
param (
    [Parameter(Mandatory=$false)] [string] $resourceGroup="smoke_bvts_resource_group",
    [Parameter(Mandatory=$false)] [string] $storageAccount="smokebvt"
)

. "C:\Framework-Scripts\secrets.ps1" 

Write-Host "Cleaning boot diag blobs from storage account $storageAccount, resource group $resourceGroup"

Write-Host "Importing the context...." 
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

Write-Host "Selecting the Azure subscription..." 
Select-AzureRmSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID" 
Set-AzureRmCurrentStorageAccount –ResourceGroupName $resourceGroup –StorageAccountName $storageAccount 

$containers=get-azurestoragecontainer
foreach ($container in $containers) {
    if ($container.Name -like "bootdiag*") { 
        Remove-AzureStorageContainer -Force -Name $container.Name  
    }
 }

# Get-AzureRmNetworkInterface -ResourceGroupName $resourceGroup | Remove-AzureRmNetworkInterface -ResourceGroupName $resourceGroup -force
# Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup | Remove-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -force
