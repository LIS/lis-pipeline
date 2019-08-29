#
#  Create a set of macines based on variants.  Variants are different machine types (standard_d2_v2), so a set of variant
#  machines all share the same base VHD image, but are (potentially) using different hardware configurations.#
#  Copies VHDs that have booted as expected to the test location where they will be prepped
#  for Azure automation
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smokework",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="vhds-under-test",
    [Parameter(Mandatory=$false)] [string] $sourceImage="sourceimage.vhd",
    [Parameter(Mandatory=$false)] [string] $destSA="smokework",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $destContainer="vhds-under-test",
    [Parameter(Mandatory=$false)] [string] $destImage="TestBase.vhd",
    [Parameter(Mandatory=$false)] [string[]] $Flavors="",
    [Parameter(Mandatory=$false)] [string[]] $requestedNames = "",

    [Parameter(Mandatory=$false)] [string] $currentSuffix="-booted-and-verified.vhd",
    [Parameter(Mandatory=$false)] [string] $newSuffix="-variant.vhd",

    [Parameter(Mandatory=$false)] [string] $network="smokeVNet",
    [Parameter(Mandatory=$false)] [string] $subnet="SmokeSubnet-1",
    [Parameter(Mandatory=$false)] [string] $NSG="SmokeNSG",
    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string] $useExistingResources="True",
    [Parameter(Mandatory=$false)] [bool] $ForceUploadVHD=$false
)

$sourceSA = $sourceSA.Trim()
$sourceRG = $sourceRG.Trim()
$sourceContainer = $sourceContainer.Trim()
$destSA = $destSA.Trim()
$destRG = $destRG.Trim()
$destContainer = $destContainer.Trim()
$Flavors = $Flavors.Trim()
$requestedNames  = $requestedNames.Trim()
$currentSuffix = $currentSuffix.Trim()
$newSuffix = $newSuffix.Trim()
$network = $network.Trim()
$subnet = $subnet.Trim()
$NSG = $NSG.Trim()
$location = $location.Trim()

[System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
if ($requestedNames -like "*,*") {
    $vmNameArray = $requestedNames.Split(',')
} else {
    $vmNameArray += $requestedNames
}

[System.Collections.ArrayList]$all_vmNames_array
$all_vmNameArray = {$vmNames_array}.Invoke()
$all_vmNameArray.Clear()

[System.Collections.ArrayList]$flavors_array
$flavorsArray = {$flavors_array}.Invoke()
$flavorsArray.Clear()
if ($Flavors -like "*,*") {
    $flavorsArray = $Flavors.Split(',')
} else {
    $flavorsArray = $Flavors
}

$vmName = $vmNameArray[0]
if ($makeDronesFromAll -ne $true -and ($vmNameArray.Count -eq 1  -and $vmName -eq "")) {
    Write-Host "Must specify either a list of VMs in RequestedNames, or use MakeDronesFromAll.  Unable to process this request."
    exit 1
}

if ($flavorsArray.Count -eq 1 -and $flavorsArray[0] -eq "" ) {
    Write-Host "Must specify at least one VM Flavor to build..  Unable to process this request."
    exit 1
}

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

login_azure $sourceRG $sourceSA $location

$timeStarted = (Get-Date -Format s).replace(":","-")

$existingGroup = Get-AzResourceGroup -Name $destRG
$status = $?
if ($status -eq $true -and $existingGroup -ne $null -and $useExistingResources -eq "False") {
    write-host "Resource group already existed.  Deleting resource group." -ForegroundColor Yellow
    Remove-AzResourceGroup -Name $destRG -Force

    write-host "Creating new resource group $destRG in loction $location"
    New-AzResourceGroup -Name $destRG -Location $location
} elseif ($status -eq $false -and $existingGroup -eq $null) {
    write-host "Creating new resource group $destRG in loction $location"
    New-AzResourceGroup -Name $destRG -Location $location
} else {
    write-host "Using existing resource group $destRG"
}

#
#  Make sure the target exists.  Create if necessary.
$existingRG=Get-AzStorageAccount -ResourceGroupName $destRG -Name $destSA
if ($? -eq $false -or $existingRG -eq $null) {
    Write-Host "Storage account $destSA did not exist.  Creating it and populating with the right containers..." -ForegroundColor Yellow
    New-AzStorageAccount -ResourceGroupName $destRG -Name $destSA -Location $location -SkuName Standard_LRS -Kind Storage

    write-host "Selecting it as the current SA" -ForegroundColor Yellow
    Set-AzCurrentStorageAccount -ResourceGroupName $destRG -StorageAccountName $destSA

    Write-Host "creating the containers" -ForegroundColor Yellow
    New-AzStorageContainer -Name $destContainer -Permission Blob
    Write-Host "Complete." -ForegroundColor Green
}
Set-AzCurrentStorageAccount -ResourceGroupName $destRG -Name $destSA

$existingContainer = Get-AzStorageContainer -Name $destContainer
if ($? -eq $false -or $existingContainer -eq $null) {
    Write-Host "creating the container" -ForegroundColor Yellow
    New-AzStorageContainer -Name $destContainer -Permission Blob
}

Set-AzCurrentStorageAccount -ResourceGroupName $sourceRG -Name $sourceSA

# Look for vhd in destination storage account
$blobArray = Get-AzStorageBlob -Container $sourceContainer
$vhdExists = $false
foreach($blob in $blobArray)
{
	if($blob.Name -eq $destImage)
	{
		$vhdExists = $true
		break
	}
}
# Copy the VHD to the destination storage account which will be used for tests
if(($ForceUploadVHD) -or (-Not $vhdExists))
{
	CopyVHDToAnotherStorageAccount $sourceSA $sourceContainer $sourceRG $destSA $destContainer $destRG $sourceImage $destImage
}else{
	Write-Host "Skipping vhd upload as vhd already exists in destination storage account."
	Write-Host "If you want to overwrite the existing vhd in destination storage account use '-ForceUploadVHD $True' ."
}


. C:\Framework-Scripts\backend.ps1

$vnetAddressPrefix = "10.0.0.0/16"
$vnetSubnetAddressPrefix = "10.0.0.0/24"

$backendFactory = [BackendFactory]::new()
$azureBackend = $backendFactory.GetBackend("AzureBackend", @(1))

$azureBackend.ResourceGroupName = $destRG
$azureBackend.StorageAccountName = $destSA
$azureBackend.sourceImage = $sourceImage
$azureBackend.ContainerName = $destContainer
$azureBackend.Location = $location
$azureBackend.VMFlavor = "Unset"
$azureBackend.NetworkName = "SmokeVNet"
$azureBackend.SubnetName = "SmokeSubnet-1"
$azureBackend.NetworkSecGroupName = "SmokeNSG"
$azureBackend.addressPrefix = $vnetAddressPrefix
$azureBackend.subnetPrefix = $vnetSubnetAddressPrefix
$azureBackend.blobURN = "None"
$azureBackend.suffix = "-Smoke-1"
$azureBackend.useInitialPW = "No"

$azureInstance = $azureBackend.GetInstanceWrapper("AzureSetup")
$azureInstance.SetupAzureRG()

$failed = $false
$comandScript = {
    param ($vmName,
            $sourceRG,
            $sourceSA,
            $sourceContainer,
            $destRG,
            $destSA,
            $destContainer,
            $location,
            $currentSuffix,
            $newSuffix,
            $NSG,
            $network,
            $subnet,
            $vmFlavor,
            $timeStarted
    )

    $logFileName = "c:\temp\transcripts\start_variants_scriptblock-" + $vmName + "-" + $vmFlavor + "-" + $timeStarted
    Start-Transcript $logFileName -Force

    . "C:\Framework-Scripts\common_functions.ps1"
    . "C:\Framework-Scripts\secrets.ps1"

    login_azure $sourceRG $sourceSA $location

    Set-AzCurrentStorageAccount -ResourceGroupName $sourceRG -StorageAccountName $sourceSA

    $blobs = Get-AzStorageBlob -Container $sourceContainer

    $blobName = "Unset"
    foreach ($blob in $blobs) {
        $blobName = $blob.Name
        Write-Verbose "Blob named $blobName was found in source container.  Seeing if it is a match..."
        if ($blobName.contains($vmName)) {
            Write-Verbose "Found blob $blobName for VM $vmName"
            break
        }
    }

    if ($blobName -eq "unset") {
        write-error "Blob for machine $vmName was not found in the container.  Cannot process."
        exit 1
    }

    Set-AzCurrentStorageAccount -ResourceGroupName $destRG -Name $destSA

    Write-verbose "Deallocating machine $vmName, if it is up"
    $runningMachines = Get-AzVM -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*"
    deallocate_machines_in_group $runningMachines $destRG $destSA $location

    $sourceURI = ("https://{0}.blob.core.windows.net/{1}/{2}" -f @($sourceSA, $sourceContainer, $blobName))

    $vmFlavLow = $vmFlavor.ToLower()

    #
    #  Just because it's up doesn't mean it's accepting connections yet.  Wait 2 minutes, then try to connect.  I tried 1 minute,
    #  but kept getting timeouts on the Ubuntu machines.
    $regionSuffix = ("-" + $location + "-" + $vmFlavor.ToLower()) -replace " ","-"
    $regionSuffix = $regionSuffix -replace "_","-"
    $imageName = $vmName + $regionSuffix
    $imageName = $imageName + $newSuffix
    $imageName = $imageName -replace ".vhd", ""

    Write-verbose "Attempting to create virtual machine $vmName from source URI $sourceURI.  This may take some time."
    C:\Framework-Scripts\launch_single_azure_vm.ps1 -vmName $vmName -resourceGroup $destRG -storageAccount $destSA -containerName $destContainer `
                                                -network $network -subnet $subnet -NSG $NSG -Location $location -VMFlavor $vmFlavLow -suffix $newSuffix `
                                                -imageIsGeneralized -generalizedBlobURI $sourceURI -Verbose
    if ($? -ne $true) {
        Write-error "Error creating VM $vmName.  This VM must be manually examined!!"
        Stop-Transcript
        exit 1
    }


    $machineIsUp = $false
    [int]$sleepCount = 0
    while ($false -eq $machineIsUp -and $sleepCount -lt 30) {
        $machineIsUp = $true
        $sleepCount = $sleepCount + 1
        $pipName = $imageName
        $ip=(Get-AzPublicIpAddress -ResourceGroupName $destRG -Name $pipName).IpAddress
        if ($ip -eq $null -or $ip.ToLower() -eq "not assigned") {
            $machineIsIP = $false
            start-sleep -Seconds 10
        } else {
            $machineIsUp = $true
            break
        }
    }

    if ($true -ne $machineIsUp) {
        Write-errpr "Error getting IP address for VM $imageName.  This VM must be manually examined!!"
        Stop-Transcript
        exit 1
    }
}

$scriptBlock = [scriptblock]::Create($comandScript)

[System.Collections.ArrayList]$copyblobs_array
$copyblobs = {$copyblobs_array}.Invoke()
$copyblobs.clear()

foreach ($vmName in $vmNameArray) {
    $blobName = $vmName
    $copyblobs += $blobName

    write-verbose "Starting variants for machine $blobName"
    foreach ($oneFlavor in $flavorsArray) {
        $vmJobName = "start_" + $oneFlavor + $blobName

        write-verbose "Launching job to start machine $blobName in flavor $oneFlavor"
        Start-Job -Name $vmJobName -ScriptBlock $scriptBlock -ArgumentList $blobName, $sourceRG, $sourceSA, $sourceContainer,`
                                                                           $destRG, $destSA, $destContainer, $location,`
                                                                           $currentSuffix, $newSuffix, $NSG, $network, `
                                                                           $subnet, $oneFlavor, $timeStarted
    }
}

Start-Sleep -Seconds 10

$allDone = $false
while ($allDone -eq $false) {
    $allDone = $true
    $numNeeded = $vmNameArray.Count + $flavors_array.Count
    $vmsFinished = 0

    foreach ($vmName in $vmNameArray) {

        $blobName = $vmName

        $blobName = $blobName.replace(".vhd","")

        foreach ($oneFlavor in $flavorsArray) {
            $vmJobName = "start_" + $oneFlavor + $blobName
            $job = Get-Job -Name $vmJobName
            $jobState = $job.State

            if ($jobState -eq "Running") {
                write-host "    Job $vmJobName is in state $jobState" -ForegroundColor Yellow
                $allDone = $false
                $logFileName = "c:\temp\transcripts\start_variants_scriptblock-" + $vmName + "-" + $oneFlavor + "-" + $timeStarted
                $logLines = Get-Content -Path $logFileName -Tail 5
                if ($? -eq $true) {
                    Write-Host "         Last 5 lines from log file $logFileName :" -ForegroundColor Cyan
                    foreach ($line in $logLines) {
                        write-host "        "$line -ForegroundColor Gray
                    }
                }
            } elseif ($jobState -eq "Failed") {
                write-host "    Job $vmJobName is in state $jobState" -ForegroundColor red
                write-host "**********************  JOB ON HOST MACHINE $vmJobName HAS FAILED TO START." -ForegroundColor Red
                # $jobFailed = $true
                $vmsFinished = $vmsFinished + 1
                $Failed = $true
            } elseif ($jobState -eq "Blocked") {
                write-host "    Job $vmJobName is in state $jobState" -ForegroundColor magenta
                write-host "**********************  HOST MACHINE $vmJobName IS BLOCKED WAITING INPUT.  COMMAND WILL NEVER COMPLETE!!" -ForegroundColor Red
                # $jobBlocked = $true
                $vmsFinished = $vmsFinished + 1
                $Failed = $true
            } else {
                $vmsFinished = $vmsFinished + 1
            }
        }
    }

    if ($allDone -eq $false) {
        Start-Sleep -Seconds 10
    } elseif ($vmsFinished -eq $numNeeded) {
        break
    }
}

if ($Failed -eq $true) {
    Write-Host "We expected $numNeeded machies, but only $vmsFinished completed.  Command has failed." -ForegroundColor Red
    exit 1
} else {
    Write-Host "Successfully created variant machines."
    exit 0
}
