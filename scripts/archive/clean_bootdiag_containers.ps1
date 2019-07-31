
param (
    [Parameter(Mandatory=$false)] [string] $resourceGroup="smoke_bvts_resource_group",
    [Parameter(Mandatory=$false)] [string] $storageAccount="smokebvt"
)

. "C:\Framework-Scripts\secrets.ps1"

Write-Host "Cleaning boot diag blobs from storage account $storageAccount, resource group $resourceGroup"

Write-Host "Importing the context...."
Import-AzContext -Path 'C:\Azure\ProfileContext.ctx'

Write-Host "Selecting the Azure subscription..."
Select-AzSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID"
Set-AzCurrentStorageAccount -ResourceGroupName $resourceGroup -StorageAccountName $storageAccount

$containers=Get-AzStorageContainer
foreach ($container in $containers) {
    if ($container.Name -like "bootdiag*") {
        Remove-AzStorageContainer -Force -Name $container.Name
    }
 }

# Get-AzNetworkInterface -ResourceGroupName $resourceGroup | Remove-AzNetworkInterface -ResourceGroupName $resourceGroup -force
# Get-AzPublicIpAddress -ResourceGroupName $resourceGroup | Remove-AzPublicIpAddress -ResourceGroupName $resourceGroup -force
