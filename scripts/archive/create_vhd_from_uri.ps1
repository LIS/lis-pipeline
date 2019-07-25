param (
    [Parameter(Mandatory=$false)] [string[]] $Incoming_vmNames,
    [Parameter(Mandatory=$false)] [string[]] $Incoming_blobURIs,

    [Parameter(Mandatory=$false)] [string] $destRG="jpl_intake_rg",
    [Parameter(Mandatory=$false)] [string] $destSA="jplintakestorageacct",
    [Parameter(Mandatory=$false)] [string] $destContainer="ready-for-bvt",
    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string] $useExistingResources = "False",

    [Parameter(Mandatory=$false)] [string] $vnetName = "SmokeVNet",
    [Parameter(Mandatory=$false)] [string] $subnetName = "SmokeSubnet-1",
    [Parameter(Mandatory=$false)] [string] $NSG = "SmokeNSG",

    [Parameter(Mandatory=$false)] [string] $suffix = "-Smoke-1",
    [Parameter(Mandatory=$false)] [string] $VMFlavor="standard_d2_v2"
)

$destSA = $destSA.Trim()
$destRG = $destRG.Trim()
$destContainer = $destContainer.Trim()
$location = $location.Trim()
$useExistingResources = $useExistingResources.Trim()
$vnetName = $vnetName.Trim()
$subnetName = $subnetName.Trim()
$NSG = $NSG.Trim()
$suffix = $suffix.Trim()
$VMFlavor = $VMFlavor.Trim()
$suffix = $suffix -replace "_","-"

$overallTimer = [Diagnostics.Stopwatch]::StartNew()
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

get-job | Stop-Job
get-job | remove-job

$timeStarted = (Get-Date -Format s).replace(":","-")
$logName = "C:\temp\transcripts\create_vhd_from_URI_-" + $timeStarted

Start-Transcript -path $logName -force

$vmNames_array=@()
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
if ($Incoming_vmNames -like "*,*") {
    $vmNameArray = $Incoming_vmNames.Split(',')
} else {
    $vmNameArray = $Incoming_vmNames
}

$blobURI_Array=@()
$blobURIArray = {$blobURI_Array}.Invoke()
$blobURIArray.Clear()
if ($IncOming_blobURIs -like "*,*") {
    $blobURIArray = $Incoming_blobURIs.Split(',')
} else {
    $blobURIArray = $Incoming_blobURIs
}

Write-Host "Names array: " $vmNameArray -ForegroundColor Yellow
$numNames = $vmNameArray.Count
Write-Host "blobs array: " $blobURIArray -ForegroundColor Yellow
$numBlobs = $blobURIArray.Count


if ($vmNameArray.Count -ne $blobURIArray.Count) {
    Write-Host "Please provide the same number of names and URIs. You have $numNames names and $numBlobs blobs" -ForegroundColor Red
    exit 1
} else {
    $numLeft = $vmNameArray.Count
    Write-Host "There are $numLeft machines to process..."  -ForegroundColor Gray
}
$vmName = $vmNameArray[0]

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

$location=($location.tolower()).Replace(" ","")

#  Log in without changing to the RG or SA.  This is intentional
login_azure

$saLength = $destSA.Length
Write-Host "Looking for storage account $destSA in resource group $destRG.  Length of name is $saLength"
#
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
#
#  Change the name of the SA to include the region, then Now see if the SA exists
$existing = Get-AzStorageAccount -ResourceGroupName $destRG -Name $destSA

if ($? -eq $false -or $existing -eq $null) {
    Write-Host "Storage account $destSA did not exist.  Creating it and populating with the right containers..." -ForegroundColor Yellow
    New-AzStorageAccount -ResourceGroupName $destRG -Name $destSA -Location $location -SkuName Standard_LRS -Kind Storage

    write-host "Selecting it as the current SA" -ForegroundColor Yellow
    Set-AzCurrentStorageAccount -ResourceGroupName $destRG -Name $destSA

    Write-Host "creating the containers" -ForegroundColor Yellow
    New-AzStorageContainer -Name "ready-for-bvt" -Permission Blob
    New-AzStorageContainer -Name "drones" -Permission Blob
    Write-Host "Complete." -ForegroundColor Green
}
Set-AzCurrentStorageAccount -ResourceGroupName $destRG -Name $destSA

Get-AzStorageBlob -Container "ready-for-bvt" -Prefix $vmName
if ($? -eq $false) {
    Write-Host "creating the BVT ready container" -ForegroundColor Yellow
    New-AzStorageContainer -Name "ready-for-bvt" -Permission Blob
}

Get-AzStorageBlob -Container "drones" -Prefix $vmName
if ($? -eq $false) {
    New-AzStorageContainer -Name "drones" -Permission Blob
    Write-Host "Complete." -ForegroundColor Green
}

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed to create validate the resource group, storage account, and container"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

. C:\Framework-Scripts\backend.ps1
# . "$scriptPath\backend.ps1"

 ## Storage
$vnetAddressPrefix = "10.0.0.0/16"
$vnetSubnetAddressPrefix = "10.0.0.0/24"

Write-Host "Initializing the back-end"
$backendFactory = [BackendFactory]::new()
$azureBackend = $backendFactory.GetBackend("AzureBackend", @(1))
Write-Host "Done Initializing the back-end"

$azureBackend.ResourceGroupName = $destRG
$azureBackend.StorageAccountName = $destSA
$azureBackend.ContainerName = $destContainer
$azureBackend.Location = $location
$azureBackend.VMFlavor = "No-Flavor"
$azureBackend.NetworkName = $vnetName
$azureBackend.SubnetName = $subnetName
$azureBackend.NetworkSecGroupName = $NSG
$azureBackend.addressPrefix = $vnetAddressPrefix
$azureBackend.subnetPrefix = $vnetSubnetAddressPrefix
$azureBackend.blobURI = ""
$azureBackend.suffix = ""
$azureBackend.useInitialPW = "Yes"

$azureInstance = $azureBackend.GetInstanceWrapper("AzureSetup")
$azureInstance.SetupAzureRG()

#
#  If the account does not exist, create it.
$scriptBlockString =
{
    param ( [string] $vmName,
            [string] $VMFlavor,
            [string] $blobURI,
            [string] $destRG,
            [string] $destSA,
            [string] $destContainer,
            [string] $location,
            [string] $suffix,
            [string] $NSG,
            [string] $vnetName,
            [string] $subnetName,
            [string] $useExistingResources,
            [string] $timeStarted
            )
    write-host "RG = $destRG"
    $logName = "C:\temp\transcripts\create_vhd_from_URI_scriptblock-" + $vmName + "-" + $timeStarted
    Start-Transcript -path $logName -force

    . C:\Framework-Scripts\common_functions.ps1
    . C:\Framework-Scripts\secrets.ps1

    $NSG = $NSG
    $subnetName =  $subnetName
    $vnetName  = $vnetName

    login_azure $destRG $destSA $location

    write-host "************* destRG is $destRG"
    write-host "************* destSA is $destSA"

    Set-AzCurrentStorageAccount -ResourceGroupName $destRG -StorageAccountName $destSA

    Write-Host "Deleting any existing VM" -ForegroundColor Green
    $runningVMs = Get-AzVM -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*" | Remove-AzVM -Force
    if ($? -eq $true -and $runningVMs -ne $null) {
        deallocate_machines_in_group $runningVMs $destRG $destSA $location
    }

    Write-Host "Clearing any old images in $destContainer with prefix $vmName..." -ForegroundColor Green
    Get-AzStorageBlob -Container $destContainer -Prefix $vmName | ForEach-Object {Remove-AzStorageBlob -Blob $_.Name -Container $destContainer}

    . C:\Framework-Scripts\backend.ps1
    # . "$scriptPath\backend.ps1"
    $backendFactory = [BackendFactory]::new()
    $azureBackend = $backendFactory.GetBackend("AzureBackend", @(1))

    $azureBackend.ResourceGroupName = $destRG
    $azureBackend.StorageAccountName = $destSA
    $azureBackend.ContainerName = $destContainer
    $azureBackend.Location = $location
    $azureBackend.UseExistingResources = $useExistingResources
    #
    #  These are intake VHDs, so they don't get a VM Flavor.
    $azureBackend.VMFlavor = $VMFlavor
    $azureBackend.NetworkName = $vnetName
    $azureBackend.SubnetName = $subnetName
    $azureBackend.NetworkSecGroupName = $NSG
    $azureBackend.addressPrefix = $vnetAddressPrefix
    $azureBackend.subnetPrefix = $vnetSubnetAddressPrefix
    $azureBackend.blobURI = $blobURI
    $azureBackend.suffix = $suffix
    $azureBackend.useInitialPW = "Yes"

    $azureBackend.enableBootDiagnostics = "No"

    $azureInstance = $azureBackend.GetInstanceWrapper($vmName)

    $azureInstance.CreateFromGeneralized()

    #
    #  Disable Cloud-Init so it doesn't try to deprovision the machine (known bug in Azure)
    write-host "Attempting to contact the machine..." -ForegroundColor Green

    $machineIsUp = $false
    [int]$sleepCount = 0
    while ($false -eq $machineIsUp -and $sleepCount -lt 30) {
        [string]$ip=$azureInstance.GetPublicIP()
        $machineIsUp = $true
        $sleepCount = $sleepCount + 1
        if ($ip -eq $null -or $ip.ToLower() -eq "not assigned") {
            $machineIsUP = $false
            start-sleep -Seconds 10
        } else {
            $machineIsUp = $true
            break
        }
    }

    if ($false -eq $machineIsUp) {
        write-host "Could not contact machine $vmName.  Machine did not get IP address after 300 seconds"
        retURI 1
    }

    $password=$TEST_USER_ACCOUNT_PAS2
    $username=$TEST_USER_ACCOUNT_NAME

    #
    # Disable cloud-init
    $disableCommand0="mv /usr/bin/cloud-init /usr/bin/cloud-init.DO_NOT_RUN_THIS"
    $runDisableCommand0="`"echo `'$password`' | sudo -S bash -c `'$disableCommand0`'`""

    #
    #  Eat the prompt and get the host into .known_hosts
    $remoteAddress = $ip
    $remoteTmp=$remoteAddress + ":/tmp"
    Write-Host "Attempting to contact remote macnhine using $remoteAddress" -ForegroundColor Green
    $timeOut = 0
    while ($true) {
        $sslReply=@(echo "y" | C:\azure-linux-automation\tools\pscp -pw $password -l $username C:\Framework-Scripts\README.md $remoteTmp)
        Write-Output "SSL Rreply is $sslReply"
        if ($sslReply -match "README" ) {
            Write-Host "Got a key request" -ForegroundColor Green
            break
        } else {
            Write-Host "No match" -ForegroundColor Yellow
            Start-Sleep -Seconds 10
            $timeOut = $timeOut + 1
            if ($timeOut -ge 60) {
                Write-Host "Failed to contact machine at IP $remoteAddress for 600 seconds.  Timeout."
                Stop-Transcript
                retURI 1
            }
        }
    }
    $sslReply=@(echo "y" | C:\azure-linux-automation\tools\pscp -pw $password -l $username C:\Framework-Scripts\README.md $remoteTmp)

    Write-Host "Setting SELinux into permissive mode" -ForegroundColor Green
    try_plink $ip $runDisableCommand0

    Write-Host "Deleting the VM so we can harvest the VHD..." -ForegroundColor Green
    $azureInstance.RemoveInstance()

    Write-Host "And cleaning up..." -ForegroundColor Green
    $azureInstance.Cleanup()

    Write-Host "Machine $vmName is ready for assimilation..." -ForegroundColor Green

    Stop-Transcript
}

$scriptBlock = [scriptblock]::Create($scriptBlockString)

$i = 0
foreach ($vmName in $vmNameArray) {
    $blobURI = $blobURIArray[$i]
    $i++
    Write-Host "Preparing machine $vmName for (URI $blobURI) service as a drone..." -ForegroundColor Green

    $jobName=$vmName + "-intake-job"
    Start-Job -Name $jobName -ScriptBlock $scriptBlock -ArgumentList $vmName,$VMFlavor,$blobURI,$destRG,$destSA,`
                                                                      $destContainer,$location,$suffix,$NSG,`
                                                                      $vnetName,$subnetName,$useExistingResources,$timeStarted
    if ($? -ne $true) {
        Write-Host "Error starting intake_machine job ($jobName) for $vmName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    Write-Host "Just launched job $jobName" -ForegroundColor Green
}

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed launch all the machine intake jobs"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

Start-Sleep -Seconds 10

$notDone = $true
while ($notDone -eq $true) {
    write-host "Status at "@(date)"is:" -ForegroundColor Green
    $notDone = $false
    foreach ($vmName in $vmNameArray) {
        $jobName=$vmName + "-intake-job"
        $job = get-job $jobName
        $jobState = $job.State
        if ($jobState -eq "Running") {
            $notDone = $true
            $useColor = "Yellow"
        } elseif ($jobState -eq "Completed") {
            $useColor="green"
        } elseif ($jobState -eq "Failed") {
            $useColor = "Red"
        } elseif ($jobState -eq "Blocked") {
            $useColor = "Magenta"
        }
        write-host "    Job $jobName is in state $jobState" -ForegroundColor $useColor
        $logFileName = "C:\temp\transcripts\create_vhd_from_URI_scriptblock-" + $vmName + "-" + $timeStarted
        $logLines = Get-Content -Path $logFileName -Tail 5
        if ($? -eq $true) {
            Write-Host "         Last 5 lines from the log file:" -ForegroundColor Cyan
            foreach ($line in $logLines) {
                write-host "        " $line -ForegroundColor Gray
            }
        }
    }
    Start-Sleep -Seconds 10
}
$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed for all the machines to complete"

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed for script create_vhd_from_uri to to complete"

Stop-Transcript
#
#  Exit with error if we failed to create the VM.  THe setup may have failed, but we can't tell that right ow
exit 0