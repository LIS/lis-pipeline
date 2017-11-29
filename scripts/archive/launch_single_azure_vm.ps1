param (
    [Parameter(Mandatory=$true)] [string] $vmName="WTF",
    [Parameter(Mandatory=$true)] [string] $resourceGroup="smoke_working_resource_group",
    [Parameter(Mandatory=$true)] [string] $storageAccount="smokework",
    [Parameter(Mandatory=$true)] [string] $containerName="vhds-under-test",

    [Parameter(Mandatory=$true)] [string] $network="SmokeVNet",
    [Parameter(Mandatory=$true)] [string] $subnet="SmokeSubnet-1",
    [Parameter(Mandatory=$true)] [string] $NSG="SmokeNSG",

    [Parameter(Mandatory=$false)] [string] $addAdminUser="",
    [Parameter(Mandatory=$false)] [string] $adminUser="",
    [Parameter(Mandatory=$false)] [string] $adminPW="",
    [Parameter(Mandatory=$false)] [string] $Location="westus",
    [Parameter(Mandatory=$false)] [string] $VMFlavor="Standard_D2",

    [Parameter(Mandatory=$false)] [string] $addressPrefix = "10.0.0.0/16",
    [Parameter(Mandatory=$false)] [string] $subnetPrefix = "10.0.0.0/24",
    [Parameter(Mandatory=$false)] [string] $blobURN,

    [Parameter(Mandatory=$false)] [string] $suffix = ".vhd",

    [Parameter(Mandatory=$false)] [switch] $imageIsGeneralized = $false,
    [Parameter(Mandatory=$false)] [string] $generalizedBlobURI = ".vhd",

    [Parameter(Mandatory=$false)] [string] $enableBootDiagnostics = "No",
    [Parameter(Mandatory=$false)] [string] $useInitialPW = "No"   
)

$vmName = $vmName.Trim()
$resourceGroup = $resourceGroup.Trim()
$storageAccount = $storageAccount.Trim()
$containerName = $containerName.Trim()
$network = $network.Trim()
$subnet = $subnet.Trim()
$NSG = $NSG.Trim()
$addAdminUser = $addAdminUser.Trim()
$adminUser = $adminUser.Trim()
$adminPW = $adminPW.Trim()
$Location = $Location.Trim()
$VMFlavor = $VMFlavor.Trim()
$addressPrefix  = $addressPrefix.Trim()
$subnetPrefix  = $subnetPrefix.Trim()
$suffix  = $suffix.Trim()
$generalizedBlobURI  = $generalizedBlobURI.Trim()
$enableBootDiagnostics  = $enableBootDiagnostics.Trim()
$useInitialPW = $useInitialPW.Trim()

Write-Host "------------------------->>> Launching VM for $vmName"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptPath\backend.ps1"

$backendFactory = [BackendFactory]::new()
$azureBackend = $backendFactory.GetBackend("AzureBackend", @(1))

$azureBackend.ResourceGroupName = $resourceGroup
$azureBackend.StorageAccountName = $storageAccount
$azureBackend.ContainerName = $containerName
$azureBackend.Location = $location
$azureBackend.VMFlavor = $VMFlavor
$azureBackend.NetworkName = $network
$azureBackend.SubnetName = $subnet
$azureBackend.NetworkSecGroupName = $NSG

$azureBackend.addressPrefix = $addressPrefix
$azureBackend.subnetPrefix = $subnetPrefix
$azureBackend.blobURN = $blobURN
$azureBackend.blobURI = $generalizedBlobURI
$azureBackend.suffix = $suffix

$azureBackend.useInitialPW = $useInitialPW

$azureBackend.enableBootDiagnostics = $enableBootDiagnostics

$azureInstance = $azureBackend.GetInstanceWrapper($vmName)
$azureInstance.Cleanup()

if ($true -ne $imageIsGeneralized) {
    write-verbose "instantinating VM $vmName from a Specialized image..."
    $azureInstance.CreateFromSpecialized()
} else {
    write-verbose "Instantinating VM $vmName from a generalized image..."
    $azureInstance.CreateFromGeneralized()
}
