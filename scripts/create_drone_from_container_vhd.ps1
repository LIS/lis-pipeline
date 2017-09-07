param (
    [Parameter(Mandatory=$false)] [string[]] $requestedNames,
    [Parameter(Mandatory=$false)] [string] $makeDronesFromAll="False",
    [Parameter(Mandatory=$false)] [string] $overwriteVHDs="False",

    [Parameter(Mandatory=$false)] [string] $sourceSA="smokesrc",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="clean-vhds",

    [Parameter(Mandatory=$false)] [string] $destSA="smokesrc",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $destContainer="safe-templates",

    [Parameter(Mandatory=$false)] [string] $location="westus",
    [Parameter(Mandatory=$false)] [string] $vmFlavor="Standard_d2_v2",

    [Parameter(Mandatory=$false)] [string] $NSG="SmokeNSG",
    [Parameter(Mandatory=$false)] [string] $network="SmokeVNet",
    [Parameter(Mandatory=$false)] [string] $subnet="SmokeSubnet-1",

    [Parameter(Mandatory=$false)] [string] $currentSuffix="-Smoke-1",
    [Parameter(Mandatory=$false)] [string] $newSuffix="-RunOnce-Primed"
)

$makeDronesFromAll = $makeDronesFromAll.Trim()
$overwriteVHDs = $overwriteVHDs.Trim()
$sourceSA = $sourceSA.Trim()
$sourceRG = $sourceRG.Trim()
$sourceContainer = $sourceContainer.Trim()
$destSA = $destSA.Trim()
$destRG = $destRG.Trim()
$destContainer = $destContainer.Trim()
$location = $location.Trim()
$vmFlavor = $vmFlavor.Trim()
$NSG = $NSG.Trim()
$network = $network.Trim()
$subnet = $subnet.Trim()
$currentSuffix = $currentSuffix.Trim()
$newSuffix = $newSuffix.Trim()

$timeStarted = (Get-Date -Format s).replace(":","-")
$logName = "C:\temp\transcripts\create_drone_from_container" + $timeStarted

Start-Transcript -Path $logName -Force
$overallTimer = [Diagnostics.Stopwatch]::StartNew()

$commandTimer = [Diagnostics.Stopwatch]::StartNew()

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

$currentSuffix = $currentSuffix -replace "_","-"
$newSuffix = $newSuffix -replace "_","-"

[System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
if ($requestedNames -like "*,*") {
    $vmNameArray = $requestedNames.Split(',')
} else {
    $vmNameArray
}

$regionSuffix = ("---" + $location + "-" + $vmFlavor.ToLower()) -replace " ","-"
$regionSuffix = $regionSuffix -replace "_","-"

$fullSuffix = $regionSuffix + $currentSuffix
$fullSuffix = $fullSuffix -replace ".vhd",""
$fullDestSuffix = $regionSuffix + $newSuffix
$fullDestSuffix = $fullDestSuffix -replace ".vhd",""

[System.Collections.ArrayList]$copyblobs_array
$copyblobs = {$copyblobs_array}.Invoke()
$copyblobs.clear()

$vmName = $vmNameArray[0]
if ($makeDronesFromAll -ne $true -and ($vmNameArray.Count -eq 1  -and $vmNameArray[0] -eq "Unset")) {
    Write-Host "Must specify either a list of VMs in RequestedNames, or use MakeDronesFromAll.  Unable to process this request."
    Stop-Transcript
    exit 1
}
    

get-job | Stop-Job
get-job | Remove-Job

login_azure $sourceRG $sourceSA $location

Set-AzureRmCurrentStorageAccount –ResourceGroupName $sourceRG –StorageAccountName $sourceSA
if ($makeDronesFromAll -eq $true) {
    
    $blobSearch = "*.vhd"
    Write-Host "Looking at all images in container $sourceContainer"
    $copyblob_new=get-AzureStorageBlob -Container $sourceContainer -Blob $blobSearch
    foreach ($blob in $copyblob_new) {
        $blobName = $blob.Name
        Write-Host "Adding blob $Name to the list"
        $copyblobs += $blobName
    }
} else {
    foreach ($vmName in $vmNameArray) {
        $fullName = $vmName + $fullSuffix
        if ($fullName.Length -gt 62) {
            Write-Warning "NOTE:  Image name $fullName is too long"
            $fullName = $fullName.substring(0, 62)
            Write-Warning "NOTE:  Image name $fullName was truncated to 62 characters"
        }
        $fullName = $fullName + ".vhd"
        Write-Host "Looking for image $fullName in container $sourceContainer"
        
        $singleBlob=get-AzureStorageBlob -Container $sourceContainer -Blob $fullName -ErrorAction SilentlyContinue
        if ($? -eq $true) {
            $singleBlobName = $singleBlob.Name
            Write-Host "Adding blob for $fullName ($singleBlobName) to the list..."
            $copyblobs += $vmName
        } else {
            Write-Host "Blob for machine $fullName was not found.  This machine cannot be processed."
        }
    }
}

if ($copyblobs.Count -eq 0) {
    Write-Host "No blobs matched source extension $currentSuffix.  No VHDs to process."
    Stop-Transcript
    exit 1
}

Remove-Item c:\temp\nix_files\make_drone.sh
Remove-Item c:\temp\nix_files\secrets.sh
Remove-Item c:\temp\nix_files\secrets.ps1
C:\azure-linux-automation\tools\dos2unix.exe -n C:\Framework-Scripts\make_drone.sh c:\temp\nix_files\make_drone.sh
C:\azure-linux-automation\tools\dos2unix.exe -n C:\Framework-Scripts\secrets.sh c:\temp\nix_files\secrets.sh
C:\azure-linux-automation\tools\dos2unix.exe -n C:\Framework-Scripts\secrets.ps1 c:\temp\nix_files\secrets.ps1

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed to set up"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

write-host "Copying blobs..."
$completeSuffix = $fullSuffix + ".vhd"
$completeDestSuffix = $fullDestSuffix + ".vhd"
C:\Framework-Scripts\copy_single_image_container_to_container.ps1 -sourceSA $sourceSA -sourceRG $sourceRG -sourceContainer $sourceContainer `
                                       -destSA $destSA -destRG $destRG -destContainer $destContainer `
                                       -sourceExtension $completeSuffix -destExtension $completeDestSuffix -location $location `
                                       -overwriteVHDs $overwriteVHDs -makeDronesFromAll $makeDronesFromAll -vmNames $vmNameArray

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed copy the blobs"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()
                                       
                                       
$scriptBlockString = 
{
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
            write-host "Checkpoint 1" -ForegroundColor Cyan
    
    $logName = "C:\temp\transcripts\create_drone_from_container-scriptblock-" + $vmName + "-" + $timeStarted
    Start-Transcript $logName -Force
    write-host "Checkpoint 2" -ForegroundColor Cyan
    . "C:\Framework-Scripts\common_functions.ps1"
    . "C:\Framework-Scripts\secrets.ps1"

    write-host "Checkpoint 3" -ForegroundColor Cyan
    
    login_azure $destRG $destSA $location

    Write-Host "Deallocating machine $vmName, if it is up"
    $runningMachines = Get-AzureRmVm -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*"
    deallocate_machines_in_group $runningMachines $destRG $destSA $location

    $newVMName = $vmName
    # $newVMName = $newVMName | % { $_ -replace ".vhd", "" }

    Write-Host "Attempting to create virtual machine $newVMName.  This may take some time." -ForegroundColor Green
    C:\Framework-Scripts\launch_single_azure_vm.ps1 -vmName $newVMName -resourceGroup $destRG -storageAccount $destSA -containerName $destContainer `
                                                    -network $network -subnet $subnet -NSG $NSG -Location $location -VMFlavor $vmFlavor `
                                                    -suffix $newSuffix -enableBootDiagnostics "No" `
                                                    -useInitialPW "Yes"
                                                    #  -addAdminUser $TEST_USER_ACCOUNT_NAME `
                                                    # -adminUser $TEST_USER_ACCOUNT_NAME -adminPW $TEST_USER_ACCOUNT_PAS2
    if ($? -ne $true) {
        Write-Host "Error creating VM $newVMName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    #
    #  Just because it's up doesn't mean it's accepting connections yet.  Wait 2 minutes, then try to connect.  I tried 1 minute,
    #  but kept getting timeouts on the Ubuntu machines.
    $username=$TEST_USER_ACCOUNT_NAME
    $password=$TEST_USER_ACCOUNT_PAS2 # Could just be "$TEST_USER_ACCOUNT_PASS1_K6"

    $regionSuffix = ("---" + $location + "-" + $vmFlavor.ToLower()) -replace " ","-"
    $regionSuffix = $regionSuffix -replace "_","-"
    $imageName = $newVMName + $regionSuffix
    $imageName = $imageName + $newSuffix
    $imageName = $imageName -replace ".vhd", ""
    if ($imageName.Length -gt 62) {
        Write-Warning "NOTE:  Image name $imageName is too long"
        $imageName = $imageName.substring(0, 62)
        Write-Warning "NOTE:  Image name is now $imageName"
        if ($imageName.EndsWith("-") -eq $true) {                
            $imageName = $imageName -Replace ".$","X"
            Write-Warning "NOTE:  Image name is ended in an illegal character.  Image name is now $imageName"
        }        
        Write-Warning "NOTE:  Image name $imageName was truncated to 62 characters"
    }
    $pipName = $imageName

    write-host "This had better be right:  $pipName"

    $gotAnAddress = $false
    while ($gotAnAddress -eq $false) {
        $ipOfDrone=Get-AzureRmPublicIpAddress -ResourceGroupName $destRG -Name $pipName
        
        if ($? -ne $true) {
            Write-Host "Error getting IP address for VM $newVMName.  Trying again in a few seconds..." -ForegroundColor red
        }
        if ($ipOfDrone.ProvisioningState -eq "Succeeded")
        {
            $ip = $ipOfDrone.IpAddress
            $gotAnAddress = $true
        } else {
            start-sleep -Seconds 10
        }
    }

    #
    #  Send make_drone to the new machine
    #
    #  The first one gets the machine added to known_hosts
    

    #
    #  Now transfer the files
    $ipTemp = $ip + ":/tmp"
    Write-Host "Copying make_drone to target $ipTemp.." -ForegroundColor Green
    while ($true) {
        $sslReply=@(Write-Output "y" | C:\azure-linux-automation\tools\pscp -pw $password -l $username C:\Framework-Scripts\README.md $ipTemp)
        Write-Output "SSL Rreply is $sslReply"
        if ($sslReply -match "README" ) {
            Write-Host "Got a key request"
            break
        } else {
            Write-Host "No match"
            Start-Sleep -Seconds 10
        }
    }
    $sslReply=@(Write-Output "y" | C:\azure-linux-automation\tools\pscp -pw $password -l $username C:\Framework-Scripts\README.md $ipTemp)

    try_pscp  C:\temp\nix_files\make_drone.sh $ipTemp
    if ($? -ne $true) {
        Write-Host "Error copying make_drone.sh to $newVMName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    Write-Host "Copying secrets to target $ipTemp.." -ForegroundColor Green
    try_pscp c:\temp\nix_files\secrets.sh $ipTemp
    if ($? -ne $true) {
        Write-Host "Error copying secrets.sh to $newVMName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    try_pscp c:\temp\nix_files\secrets.ps1 $ipTemp
    if ($? -ne $true) {
        Write-Host "Error copying secrets.ps1 to $newVMName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    $chmodCommand="chmod 755 /tmp/make_drone.sh"
    $runDroneCommand="/tmp/make_drone.sh"
    $linuxChmodCommand="`"echo $password | sudo -S bash -c `'$chmodCommand`'`""
    $linuxDroneCommand="`"echo $password | sudo -S bash -c `'$runDroneCommand`'`""

    Write-Host "Using plink to chmod the script"
    #
    #  chmod the thing
    try_plink $ip $linuxChmodCommand
    if ($? -ne $true) {
        Write-Host "Error running chmod command.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    #
    #  Now run make_drone
    Write-Host "And now running make_drone.  This may take a few minutes.  How about a nice cup of very strong tea?"
    try_plink $ip $linuxDroneCommand
    if ($? -ne $true) {
        Write-Host "Error running make_drone command.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    Stop-Transcript
}

$scriptBlock = [scriptblock]::Create($scriptBlockString)

$dronejobs_array=@()
$droneJobs = {$dronejobs_array}.Invoke()
$droneJobs.clear()

write-host "Setting up the drone jobs..."

get-job | Stop-Job
get-job | Remove-Job


Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA
foreach ($vmName in $vmNameArray) { 
    $jobName=$vmName + "-drone-job"
    Start-Job -Name $jobName -ScriptBlock $scriptBlock -ArgumentList $vmName,$sourceRG,$sourceSA,$sourceContainer,$destRG,$destSA,`
                                                                      $destContainer,$location,$currentSuffix,$newSuffix,$NSG,`
                                                                      $network,$subnet,$vmFlavor,$timeStarted
    if ($? -ne $true) {
        Write-Host "Error starting make_drone job ($jobName) for $vmName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    Write-Host "Just launched job $jobName"
}

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed get to machine launch"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

start-sleep -Seconds 10

write-host "Checking make_drone jobs..."
$notDone = $true
while ($notDone -eq $true) {
    write-host "Status at $(@(date)) is:" -ForegroundColor Green
    $notDone = $false
    foreach ($vmName in $vmNameArray) {
        $jobName=$vmName + "-drone-job"
        $job = get-job $jobName
        $jobState = $job.State
        write-host "    Job $jobName is in state $jobState" -ForegroundColor Yellow
        if ($jobState -eq "Running") {
            $notDone = $true
            $logName = "C:\temp\transcripts\create-drone-from-container-scriptblock-" + $vmName + "-" + $timeStarted            
            $logLines = Get-Content -Path $logName -Tail 5
            if ($? -eq $true) {
                Write-Host "         Last 5 lines from the script log file:" -ForegroundColor Cyan
                foreach ($line in $logLines) {
                    write-host "        "$line -ForegroundColor Gray
                }
            }
        }
    }
    Start-Sleep -Seconds 10
}

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed to make the drones"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()


Write-Host "All jobs have completed.  Checking results (this will take a moment...)"

#
#  Get the results of that
$regionSuffix = ("---" + $location + "-" + $vmFlavor.ToLower()) -replace " ","-"
$regionSuffix = $regionSuffix -replace "_","-"
$fullDestSuffix = $regionSuffix + $newSuffix

$status = c:\Framework-Scripts\run_command_on_machines_in_group.ps1 -requestedNames $requestedNames -destSA $destSA -destRG $destRG `
                                                                    -suffix $newSuffix -location $location -command "/bin/uname -a" `
                                                                    -retryCount 5
$status
$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed verify connectivity"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()


if ($status -contains "FAILED to establish PSRP connection") {
    Write-Host "Errors found in this job, so adding the job output to the log..."
    
    $jobs = get-job
    foreach ($job in $jobs) {
        $jobName = $job.Name
        Write-Host ""
        Write-Host "------------------------------------------------------------------------------------------------------"
        Write-Host "                             JOB LOG FOR JOB $jobname"   
        Write-Host "------------------------------------------------------------------------------------------------------"
        Write-Host ""
        $job | receive-job
    }
}

get-job | stop-job
get-job | remove-job

$overallTimer.Stop()
$elapsed = $overallTimer.Elapsed
Write-Host "It required $elapsed to execute this script"

Stop-Transcript

if ($sessionFailed -eq $true) {    
    exit 1
} else {
    exit 0
}