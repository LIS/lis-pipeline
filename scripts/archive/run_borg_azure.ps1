#
#  Run the Basic Operations and Readiness Gateway on Azure.  This script will:
#      - Copy a VHD from the templates container to a working one
#      - Create a VM around the VHD and launch it.  It is assumed that the VHD has a
#        properly configured RunOnce set up
#      - Periodically poll the VM and check for status.  Report same to console unitl
#        either SUCCESS or FAILURE is perceived.
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
#  Azure information

param (
    #
    #  Azure RG for all accounts and containers
    [Parameter(Mandatory=$false)] [string] $sourceResourceGroupName="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceStorageAccountName="smokesrc",
    [Parameter(Mandatory=$false)] [string] $sourceContainerName="drones",

    [Parameter(Mandatory=$false)] [string] $workingResourceGroupName="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $workingStorageAccountName="smokework",
    [Parameter(Mandatory=$false)] [string] $workingContainerName="vhds-under-test",

    [Parameter(Mandatory=$false)] [string] $sourceURI="Unset",

    #
    #  A place with the contents of Last Known Good.  This is similar to Latest for packagee
    [Parameter(Mandatory=$false)] [string] $testOutputResourceGroup="smoke_output_resoruce_group",
    [Parameter(Mandatory=$false)] [string] $testOutputStorageAccountName="smoketest",
    [Parameter(Mandatory=$false)] [string] $testOutputContainerName="last-known-good-vhds",

    #
    #  Our location & flavor
    [Parameter(Mandatory=$false)] [string] $location="westus",
    [Parameter(Mandatory=$false)] [string] $vmFlavor="Standard_D2_V2",

    #
    #  If set, which is the default, this will re-create the destination RG
    [Parameter(Mandatory=$false)] [string] $CleanRG="false"
)

$sourceResourceGroupName = $sourceResourceGroupName.Trim()
$sourceStorageAccountName = $sourceStorageAccountName.Trim()
$sourceContainerName = $sourceContainerName.Trim()
$workingResourceGroupName = $workingResourceGroupName.Trim()
$workingStorageAccountName = $workingStorageAccountName.Trim()
$workingContainerName = $workingContainerName.Trim()
$sourceURI = $sourceURI.Trim()
$testOutputResourceGroup = $testOutputResourceGroup.Trim()
$testOutputStorageAccountName = $testOutputStorageAccountName.Trim()
$testOutputContainerName = $testOutputContainerName.Trim()
$location = $location.Trim()
$vmFlavor = $vmFlavor.Trim()
$CleanRG = $CleanRG.Trim()

get-job | Stop-Job  > $null
get-job | remove-job  > $null

$global:logFileTime = (Get-Date -Format s).replace(":","-")
$logName = "C:\temp\transcripts\run_borg_azure-" + $logFileTime
Start-Transcript -path $logName -force

$overallTimer = [Diagnostics.Stopwatch]::StartNew()

Set-StrictMode -Version 2.0

. C:\Framework-Scripts\common_functions.ps1
. C:\Framework-Scripts\secrets.ps1

$global:sourceResourceGroupName=$sourceResourceGroupName
$global:sourceStorageAccountName=$sourceStorageAccountName
$global:sourceContainerName=$sourceContainerName
$global:location=$location

$global:VMFlavor=$VMFlavor.ToLower()

$global:workingResourceGroupName=$workingResourceGroupName
$global:workingStorageAccountName=$workingStorageAccountName
$global:workingContainerName=$workingContainerName

$global:sourceURI=$sourceURI

$global:testOutputResourceGroup=$testOutputResourceGroup
$global:testOutputContainerName=$testOutputContainerName
$global:workingContainerName=$workingContainerName

$global:useSourceURI=[string]::IsNullOrEmpty($global:sourceURI)
$global:CleanRG = $CleanRG

#
#  The machines we're working with
$global:neededVms_array=@()
$global:neededVms = {$neededVms_array}.Invoke()
$global:neededVms.Clear()

$global:copyblobs_array=@()
$global:copyblobs = {$copyblobs_array}.Invoke()
$global:copyblobs.Clear()

$global:completed=0
$global:elapsed=0
#
#  Timer interval in msec.
$global:interval=500
$global:boot_timeout_minutes=20
$global:boot_timeout_intervals_per_minute=(60*(1000/$global:interval))
$global:boot_timeout_intervals= ($global:interval * $global:boot_timeout_intervals_per_minute) * $global:boot_timeout_minutes

#
#  Machine counts and status
$global:num_expected=0
$global:num_remaining=0
$global:failed=0
$global:booted_version="Unknown"
$global:timer_is_running = 0

#
#  Session stuff
#
$global:o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$global:cred=make_cred

class MonitoredMachine {
    [string] $name="unknown"
    [string] $status="Unitialized"
    [string] $ipAddress="Unitialized"
    $session=$null
}
[System.Collections.ArrayList]$global:monitoredMachines = @()

$timer=New-Object System.Timers.Timer

class MachineLog {
    [string] $name="unknown"
    [string] $job_log
    [string] $job_name
}
[System.Collections.ArrayList]$global:machineLogs = @()

$regionSuffix = ("---" + $global:location + "-" + $global:VMFlavor) -replace " ","-"
$regionSuffix = $regionSuffix -replace "_","-"

$fullSuffix = $regionSuffix + "-BORG"

function copy_azure_machines {
    if ($global:useSourceURI -eq $false)
    {
        #
        #  In the source group, stop any machines, then get the keys.
        Set-AzCurrentStorageAccount -ResourceGroupName $global:sourceResourceGroupName -StorageAccountName $global:sourceStorageAccountName > $null

        Write-Host "Stopping any currently running machines in source resource group $global:sourceResourceGroupName / $global:sourceStorageAccountName / $global:sourceContainerName..."  -ForegroundColor green
        $runningVMs = Get-AzVM -ResourceGroupName $global:sourceResourceGroupName
        deallocate_machines_in_group $runningVMs $global:sourceResourceGroupName $global:sourceStorageAccountName $global:location

        $sourceKey=Get-AzStorageAccountKey -ResourceGroupName $global:sourceResourceGroupName -Name $global:sourceStorageAccountName
        $sourceContext=New-AzStorageContext -StorageAccountName $global:sourceStorageAccountName -StorageAccountKey $sourceKey[0].Value

        $blobs = Get-AzStorageBlob -Container $global:sourceContainerName

        #
        #  Switch to the target resource group
        Set-AzCurrentStorageAccount -ResourceGroupName $global:workingResourceGroupName -StorageAccountName $global:workingStorageAccountName > $null

        Write-Host "Stopping and deleting any currently running machines in  target storage $global:workingResourceGroupName / $global:workingStorageAccountName / $global:workingContainerName..."  -ForegroundColor green
        $runningVMs = Get-AzVM -ResourceGroupName $global:workingResourceGroupName
        deallocate_machines_in_group $runningVMs $global:workingResourceGroupName $global:workingStorageAccountName $global:location
        Get-AzStorageBlob -Blob "*" -Container $global:workingContainerName | Remove-AzStorageBlob -Force

        Write-Host "Getting the storage account access keys.."
        $destKey=Get-AzStorageAccountKey -ResourceGroupName $global:workingResourceGroupName -Name $global:workingStorageAccountName
        $destContext=New-AzStorageContext -StorageAccountName $global:workingStorageAccountName -StorageAccountKey $destKey[0].Value

        Write-Host "Preparing the individual machines..." -ForegroundColor green

        foreach ($oneblob in $blobs) {
            $fullName=$oneblob.Name

            $bar=$fullName.Replace("---","{")
            $nameParts = $bar.split("{")
            $targetName = $nameParts[0] + $fullSuffix

            if ($targetName.Length -gt 62) {
                Write-Warning "NOTE:  Image name $targetName is too long"
                $targetName = $targetName.substring(0, 62)
                Write-Warning "NOTE:  Image name is now $targetName"
                if ($targetName.EndsWith("-") -eq $true) {
                    $targetName = $targetName -Replace ".$","X"
                    Write-Warning "NOTE:  Image name is ended in an illegal character.  Image name is now $imagtargetNameeName"
                }
                Write-Warning "NOTE:  Image name $targetName was truncated to 62 characters"
            }
            $vmName = $targetName
            $targetName = $targetName + ".vhd"

            $global:neededVMs.Add($vmName)

            Write-Host "     --------- Initiating job to copy VHD $fullName from $global:sourceContainerName to $global:workingContainerName as $targetName..." -ForegroundColor Yellow
            $blob = Start-AzStorageBlobCopy -SrcBlob $fullName -DestContainer $global:workingContainerName `
                                                -SrcContainer $global:sourceContainerName -DestBlob $targetName `
                                                -Context $sourceContext -DestContext $destContext

            $global:copyblobs += $targetName
        }
    } else {
        Write-Host "Clearing the destination container..."  -ForegroundColor green
        Write-Host "Deleting any currently running machines in  target storage $global:workingResourceGroupName / $global:workingStorageAccountName / $global:workingContainerName..."  -ForegroundColor green

        Get-AzStorageBlob -Container $global:workingContainerName -blob * | ForEach-Object {Remove-AzStorageBlob -Blob $_.Name -Container $global:workingContainerName -Force}  > $null

        foreach ($singleURI in $global:URI) {
            Write-Host "Preparing to copy disk by URI.  Source URI is $singleURI"  -ForegroundColor green

            $splitUri=$singleURI.split("/")
            $lastPart=$splitUri[$splitUri.Length - 1]

            $sourceName = $lastPart
            $bar=$sourceName.Replace("---","{")
            $nameParts = $bar.split("{")
            $targetName = $nameParts[0] + $fullSuffix
            if ($targetName.Length -gt 62) {
                Write-Warning "NOTE:  Image name $targetName is too long"
                $targetName = $targetName.substring(0, 62)
                Write-Warning "NOTE:  Image name is now $targetName"
                if ($targetName.EndsWith("-") -eq $true) {
                    $targetName = $targetName -Replace ".$","X"
                    Write-Warning "NOTE:  Image name is ended in an illegal character.  Image name is now $imagtargetNameeName"
                }
                Write-Warning "NOTE:  Image name $targetName was truncated to 62 characters"
            }
            $vmName = $targetName
            $targetName = $targetName + ".vhd"

            $global:neededVMs.Add($sourceName)

            Write-Host "Initiating job to copy VHD $targetName from  $global:sourceContainerName to working $global:workingContainerName..." -ForegroundColor Yellow
            $blob = Start-AzStorageBlobCopy -SrcBlob $singleURI -DestContainer $global:workingContainerName -SrcContainer $global:sourceContainerName -DestBlob $targetName -Context $sourceContext -DestContext $destContext

            $global:copyblobs += $targetName
        }
    }

    start-sleep 10

    Write-Host "All copy jobs have been launched.  Waiting for completion..." -ForegroundColor green
    Write-Host ""
    $stillCopying = $true
    while ($stillCopying -eq $true) {
        $stillCopying = $false
        $reset_copyblobs = $true

        Write-Host "Checking copy status..." -ForegroundColor Green
        while ($reset_copyblobs -eq $true) {
            $reset_copyblobs = $false
            foreach ($blob in $global:copyblobs) {
                $status = Get-AzStorageBlobCopyState -Blob $blob -Container $global:workingContainerName -ErrorAction SilentlyContinue
                if ($? -eq $false) {
                    Write-Host "     **** Could not get copy state for job $blob.  Job may not have started." -ForegroundColor Red
                    # $copyblobs.Remove($blob)
                    # $reset_copyblobs = $true
                } elseif ($status.Status -eq "Pending") {
                    $bytesCopied = $status.BytesCopied
                    $bytesTotal = $status.TotalBytes
                    $pctComplete = ($bytesCopied / $bytesTotal) * 100
                    Write-Host "     --------- Job $blob has copied $bytesCopied of $bytesTotal bytes ($pctComplete %)." -ForegroundColor Yellow
                    $stillCopying = $true
                } else {
                    $exitStatus = $status.Status
                    if ($exitStatus -eq "Success") {
                        Write-Host "     **** Job $blob has completed successfully." -ForegroundColor Green
                    } else {
                        Write-Host "     **** Job $blob has failed with state $exitStatus." -ForegroundColor Red
                    }
                    # $copyblobs.Remove($blob)
                    # $reset_copyblobs = $true
                    # break
                }
            }
        }

        if ($stillCopying -eq $true) {
            Start-Sleep -Seconds 15
        } else {
            Write-Host "All copy jobs have completed.  Rock on."
        }
    }
}


function create_azure_topology {

    . C:\Framework-Scripts\backend.ps1
    # . "$scriptPath\backend.ps1"

     ## Storage
    $vnetAddressPrefix = "10.0.0.0/16"
    $vnetSubnetAddressPrefix = "10.0.0.0/24"

    $backendFactory = [BackendFactory]::new()
    $azureBackend = $backendFactory.GetBackend("AzureBackend", @(1))

    $azureBackend.ResourceGroupName = $global:workingResourceGroupName
    $azureBackend.StorageAccountName = $global:workingStorageAccountName
    $azureBackend.ContainerName = "drones"
    $azureBackend.Location = $global:location
    $azureBackend.VMFlavor = $global:VMFlavor
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

    $requestedNames = ""
    foreach ($vmName in $global:neededVms) {
        $requestedNames = $requestedNames + $vmName + " "

        $machine = new-Object MonitoredMachine
        $machine.name = $vmName

        $machine.status = "Booting" # $status
        $global:monitoredMachines.Add($machine)

        $global:num_remaining += 1
        $jobname=$vmName + "-VMStart"

        $machine_log = New-Object MachineLog
        $machine_log.name = $vmName
        $machine_log.job_name = $jobname
        $global:machineLogs.Add($machine_log)

        $resourceGroup="smoke_working_resource_group"
        $storageAccount="smokework"
        $containerName="vhds-under-test"

        $network="SmokeVNet"
        $subnet="SmokeSubnet-1"
        $NSG="SmokeNSG"

        $VMFlavor="Standard_D2_V2"

        $addressPrefix = "10.0.0.0/16"
        $subnetPrefix = "10.0.0.0/24"

        $suffix = "-BORG.vhd"

        $scriptText = {
            param (
                [Parameter(Mandatory=$false)] [string] $vm_name,
                [Parameter(Mandatory=$false)] [string] $rg,
                [Parameter(Mandatory=$false)] [string] $sa,
                [Parameter(Mandatory=$false)] [string] $cn,
                [Parameter(Mandatory=$false)] [string] $nw,
                [Parameter(Mandatory=$false)] [string] $sn,
                [Parameter(Mandatory=$false)] [string] $nsg,
                [Parameter(Mandatory=$false)] [string] $loc,
                [Parameter(Mandatory=$false)] [string] $flav,
                [Parameter(Mandatory=$false)] [string] $apf,
                [Parameter(Mandatory=$false)] [string] $spf,
                [Parameter(Mandatory=$false)] [string] $sfc
            )

            C:\Framework-Scripts\launch_single_azure_vm.ps1 -vmName $vm_name -resourceGroup $rg -storageAccount $sa -containerName $cn `
                                                            -network $nw -subnet $sn -NSG $nsg -location $loc -VMFlavor $flav `
                                                            -addressPrefix $apf -subnetPrefix $spf -suffix $sfc -useInitialPW "No"
        }

        $scriptBlock = [scriptblock]::Create($scriptText)

        Start-Job -Name $jobname -ScriptBlock $scriptBlock -ArgumentList $vmName,$resourceGroup,$storageAccount,$containerName,$network,$subnet,`
                                                                         $NSG,$global:location,$vmFlavor,$addressPrefix,$subnetPrefix,$suffix
    }

    foreach ($singleLog in $global:machineLogs) {

        $jobname=$singleLog.job_name
        $jobStatus=get-job -Name $jobName
        $jobState = $jobStatus.State

        if ($jobState -eq "Failed") {
            Write-Host " ---------> Azure boot Job $jobName failed to lanch.  Error information is $jobStatus.Error" -ForegroundColor yellow
            $global:num_remaining -= 1
            if ($global:num_remaining -eq 0) {
                $global:completed = 1
            }
        }
        elseif ($jobState -eq "Completed")
        {
            Write-Host " ---------> Azure boot job $jobName completed while we were waiting.  We will check results later." -ForegroundColor green
            $global:num_remaining -= 1
            if ($global:num_remaining -eq 0) {
                $global:completed = 1
            }
        }
        else
        {
            Write-Host "      Azure boot job $jobName launched successfully." -ForegroundColor green
        }
    }
}

$action={
    . C:\Framework-Scripts\common_functions.ps1
    . C:\Framework-Scripts\secrets.ps1

    $logName = "C:\temp\transcripts\run_borg_azure-timer_scriptblock-" + $global:logFileTime
    Start-Transcript -path $logName -force

    function checkMachine ([MonitoredMachine]$machine) {
        $machineName=$machine.name
        $machineStatus=$machine.status

        if ($machineStatus -eq "Completed" -or $global:num_remaining -eq 0) {
            Write-Host "    **** Machine $machineName is in state $machineStatus, which is complete, or there are no remaining machines" -ForegroundColor green
            Stop-Transcript
            return 0
        }

        if ($machineStatus -ne "Booting") {
            Write-Host "    **** ??? Machine $machineName was not in state Booting.  Cannot process" -ForegroundColor red
            Stop-Transcript
            return 1
        }

        #
        #  Attempt to create the PowerShell PSRP session
        #
        $machineIsUp = $false
        $expected_vers = "Not-Set"
        $installed_vers = "Not-Detected"
        foreach ($localMachine in $global:monitoredMachines) {
            [MonitoredMachine]$monitoredMachine=$localMachine

            if ($localMachine.Name -eq $machineName) {
                if ($localMachine.session -eq $null) {
                    $localSession = create_psrp_session $machineName $global:workingResourceGroupName $global:workingStorageAccountName `
                                                        $global:location $global:cred $global:o


                    if ($localSession -ne $null) {
                        Write-Host "Creating PowerShell Remoting session to machine $machineName"  -ForegroundColor green
                        $machineIsUp = $true
                        $localMachine.session = $localSession
                    }
                } else {
                    # Write-Host "Re-using old session"
                    $machineIsUp = $true
                    $localSession = $localMachine.session
                }
                break
            }
        }

        if ($machineIsUp -eq $true) {
            $exceptionCaught = $false
            try {
                $installed_vers=invoke-command -session $localSession -ScriptBlock {/bin/uname -r}
                # Write-Host "$machineName installed version retrieved as $installed_vers" -ForegroundColor Cyan

                #
                #  This must be done as root
                $command = "/usr/bin/powershell get-content /HIPPEE/expected_version"
                $password=$TEST_USER_ACCOUNT_PASS
                $runCommand = "echo $password | sudo -S bash -c `'$command`'"
                $commandBLock=[scriptblock]::Create($runCommand)
                $expected_vers = invoke-command -session $localSession -ScriptBlock $commandBLock -ArgumentList $command
                # Write-Host "$machineName Expected version retrieved as $expected_vers" -ForegroundColor Cyan
                $expected_vers = ($expected_vers.Split(" "))[0]
            }
            Catch
            {
                Write-Host "Caught exception attempting to verify Azure installed kernel version.  Ignoring..." -ForegroundColor red
                $installed_vers="Not Detected"
                $expected_vers = "Communication Failure"
                Remove-PSSession -Session $localSession > $null
                $localMachine.session = $null
                $exceptionCaught = $true

                Remove-PSSession -Session $localSession
                $localMachine.session = $null
            }

            # Write-Host "Looking for version $expected_verDeb or $expected_verCent"
            if ($exceptionCaught -eq $false) {
                if ($expected_vers -eq "") {
                    write-host "Expected_vers was unset" -ForegroundColor Red
                    $expected_vers = "unset"
                }

                if ($installed_vers -eq "") {
                    Write-Host "Installed_vers was unset"
                    $Installed_vers = "Unknown"
                }

                if ($expected_vers.CompareTo($installed_vers) -ne 0) {
                    if (($global:elapsed % $global:boot_timeout_intervals_per_minute) -eq 0) {
                        Write-Host "     Machine $machineName reports up, but the kernel version is $installed_vers when we expected" -ForegroundColor Cyan
                        Write-Host "             $expected_vers.  Waiting to see if it reboots." -ForegroundColor Cyan
                        Write-Host ""
                    }
                    # Write-Host "(let's see if there is anything running with the name Kernel on the remote machine)"
                    # invoke-command -session $localMachine.session -ScriptBlock {ps -efa | grep -i linux}
                } else {
                    Write-Host "    *** Machine $machineName came back up as expected.  kernel version is $installed_vers" -ForegroundColor green
                    $localMachine.Status = "Completed"
                    $global:num_remaining -= 1
                }
            } else {
                if (($global:elapsed % $global:boot_timeout_intervals_per_minute) -eq 0) {
                        Write-Host "     Machine $machineName reports up, but we caught an exception when attempting to contact it." -ForegroundColor Magenta
                        Write-Host "             Waiting to see if it reboots." -ForegroundColor Magenta
                        Write-Host ""
                    }
            }
        } else {
            if (($global:elapsed % $global:boot_timeout_intervals_per_minute) -eq 0) {
                Write-Host "Machine $machineName is not up yet, as far as we know..." -ForegroundColor yellow
            }

        }
    }

    if ($global:timer_is_running -eq 0) {
        Write-Host "Timer is not running"
        Stop-Transcript
        return
    }

    $global:elapsed=$global:elapsed+$global:interval
    # Write-Host "Checking elapsed = $global:elapsed against interval limit of $global:boot_timeout_intervals" -ForegroundColor Yellow

    if ($global:elapsed -ge $global:boot_timeout_intervals) {
        Write-Host "Elapsed is $global:elapsed"
        Write-Host "Intervals is $global:boot_timeout_intervals"
        Write-Host "Timer has timed out." -ForegroundColor red
        $global:completed=1
        Stop-Transcript
        return
    }

    #
    #  Check for Hyper-V completion
    #
    foreach ($localMachine in $global:monitoredMachines) {
        [MonitoredMachine]$monitoredMachine=$localMachine
        $monitoredMachineName=$monitoredMachine.name
        $monitoredMachineStatus=$monitoredMachine.status

        foreach ($singleLog in $global:machineLogs) {
            #
            #  Don't even try if the new-vm hasn't completed...
            #
            $jobStatus=$null
            if ($singleLog.name -eq $monitoredMachineName) {
                $jobStatus = get-job $singleLog.job_name
                if ($? -eq $true) {
                    $jobStatus = $jobStatus.State
                } else {
                    $jobStatus = "Unknown"
                }

                if ($jobStatus -ne $null -and ($jobStatus -eq "Completed" -or $jobStatus -eq "Failed")) {
                    if ($jobStatus -eq "Completed") {
                        if ($monitoredMachineStatus -ne "Completed") {
                            checkMachine $monitoredMachine
                        }
                    } elseif ($jobStatus -eq "Failed") {
                        Write-Host "Job to start VM $monitoredMachineName failed.  Any log information provided follows:"
                        receive-job $jobname
                    }
                } elseif ($jobStatus -eq $null -and $monitoredMachineStatus -ne "Completed") {
                    checkMachine $monitoredMachine
                }
            }
        }
    }

    if ($global:num_remaining -eq 0) {
        $global:completed=1
    }

    if (($global:elapsed % 10000) -eq 0) {
        if ($global:num_remaining -eq 0) {
            Write-Host "***** All machines have reported in."  -ForegroundColor magenta
            if ($global:failed -eq $true) {
                Write-Host "One or more machines have failed to boot.  This job has failed." -ForegroundColor Red
            }
            Write-Host "Stopping the timer" -ForegroundColor green
            $global:completed=1
            return
        }

        Write-Host ""
        Write-Host "Waiting for remote machines to complete all testing.  There are $global:num_remaining machines left.." -ForegroundColor green

        foreach ($localMachine in $global:monitoredMachines) {
            [MonitoredMachine]$monitoredMachine=$localMachine

            $monitoredMachineName=$monitoredMachine.name
            $monitoredMachineStatus=$monitoredMachine.status

            $calledIt = $false
            foreach ($singleLog in $global:machineLogs) {
                $singleLogName = $singleLog.name
                $singleLogJobName = $singleLog.job_name

                if ($singleLogName -eq $monitoredMachineName) {
                    if ($monitoredMachine.status -ne "Completed") {
                        $jobStatusObj = get-job $singleLogJobName -ErrorAction SilentlyContinue
                        if ($? -eq $true) {
                            $jobStatus = $jobStatusObj.State
                        } else {
                            $jobStatus = "Unknown"
                        }
                    } else {
                        $jobStatus = "Completed"
                    }

                    if ($jobStatus -eq "Completed" -or $jobStatus -eq "Failed") {
                        if ($jobStatus -eq "Completed") {
                           if ($monitoredMachineStatus -eq "Completed") {
                                Write-Host "    ***** Machine $monitoredMachineName has completed..." -ForegroundColor green
                                $calledIt = $true
                            } else {
                                Write-Host "     ----- Testing of machine $monitoredMachineName is in progress..." -ForegroundColor Yellow

                                if ($monitoredMachine.session -eq $null) {

                                    $localSession = create_psrp_session $monitoredMachineName $global:workingResourceGroupName $global:workingStorageAccountName `
                                                                        $global:location $cred $o

                                    if ($localSession -ne $null) {
                                        $monitoredMachine.session = $localSession
                                        $machineIsUp = $true
                                    } else {
                                        $monitoredMachine.session = $null
                                    }
                                }

                                if ($monitoredMachine.session -ne $null) {
                                    $localSession = $localMachine.session
                                    Write-Host "          Last three lines of the log file for machine $monitoredMachineName ..." -ForegroundColor Magenta
                                    try {
                                        $last_lines=invoke-command -session $localSession -ScriptBlock { get-content /opt/microsoft/borg_progress.log }
                                        if ($? -eq $true) {
                                            $last_lines | write-host -ForegroundColor Magenta
                                        } else {
                                            Write-Host "       +++++ Error when attempting to retrieve the log file from the remote host.  It may be rebooting..." -ForegroundColor Yellow
                                        }
                                    }
                                    catch
                                    {
                                        Write-Host "     +++++ Error when attempting to retrieve the log file from the remote host.  It may be rebooting..." -ForegroundColor Yellow
                                    }
                                }
                                $calledIt = $true
                            }
                        } elseif ($jobStatus -eq "Failed") {
                            Write-Host "    *** Job $singleLogName failed to start." -ForegroundColor Red
                            Write-Host "        Log information, if any, follows:" -ForegroundColor Red
                            receive-job $singleLogJobName
                            $calledIt = $true
                        }
                    } elseif ($jobStatusObj -ne $null) {
                        $message="     ----- The job starting VM $monitoredMachineName has not completed yet.  The current state is " + $jobStatus
                        Write-Host $message -ForegroundColor Yellow
                        $calledIt = $true
                    }

                    break
                }
            }

            if ($calledIt -eq $false -and $monitoredMachineStatus -ne "Completed") {
                Write-Host " ----- Machine $monitoredMachineName has not completed yet" -ForegroundColor yellow
            }
        }
    }
    [Console]::Out.Flush()
    Stop-Transcript
}

Get-EventSubscriber -SourceIdentifier "AzureBORGTimer" | Unregister-Event

Write-Host "    " -ForegroundColor green
Write-Host "                 **********************************************" -ForegroundColor yellow
Write-Host "                 *                                            *" -ForegroundColor yellow
Write-Host "                 *            Microsoft Linux Kernel          *" -ForegroundColor yellow
Write-Host "                 *     Basic Operational Readiness Gateway    *" -ForegroundColor yellow
Write-Host "                 * Host Infrastructure Validation Environment *" -ForegroundColor yellow
Write-Host "                 *                                            *" -ForegroundColor yellow
Write-Host "                 *           Welcome to the BORG HIVE         *" -ForegroundColor yellow
Write-Host "                 **********************************************" -ForegroundColor yellow
Write-Host "    "
Write-Host "          Initializing the CUBE (Customizable Universal Base of Execution)" -ForegroundColor yellow
Write-Host "    "

#
#  Clean up the sentinel files
#
Write-Host "   "
Write-Host "                                BORG CUBE is initialized"                   -ForegroundColor Yellow
Write-Host "              Starting the Dedicated Remote Nodes of Execution (DRONES)" -ForegroundColor yellow
Write-Host "    "

get-job | Stop-Job
get-job | Remove-Job

login_azure

$date1 = Get-Date -Date "01/01/1970"
$date2 = Get-Date
$seconds = (New-TimeSpan -Start $date1 -End $date2).TotalSeconds

$timerName="AzureBORGTimer-" + $seconds
Write-Host "Using timer name $timerName"

Write-Host "Looking for storage account $global:workingStorageAccountName in resource group $global:workingResourceGroupName."
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

$existingGroup = Get-AzResourceGroup -Name $global:workingResourceGroupName
if ($? -eq $true -and $existingGroup -ne $null -and $global:CleanRG -eq $true) {
    write-host "Resource group already existed.  Deleting resource group." -ForegroundColor Yellow
    Remove-AzResourceGroup -Name $global:workingResourceGroupName -Force

    write-host "Creating new resource group $global:workingResourceGroupName in loction $global:location"
    New-AzResourceGroup -Name $global:workingResourceGroupName -Location $global:location
} elseif ($existingGroup -eq $null) {
    write-host "Creating new resource group $global:workingResourceGroupName in loction $global:location"
    New-AzResourceGroup -Name $global:workingResourceGroupName  -Location $global:location
}

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed set up the resorurce group"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

#
#
#  Change the name of the SA to include the region, then Now see if the SA exists
Get-AzStorageAccount -ResourceGroupName $global:workingResourceGroupName  -Name $global:workingStorageAccountName
if ($? -eq $false -or $global:CleanRG -eq $true) {
    if ($? -eq $false) {
        New-AzStorageAccount -ResourceGroupName $global:workingResourceGroupName -Name $global:workingStorageAccountName `
                                  -Kind Storage -Location $global:location -SkuName Standard_LRS
        # Remove-AzStorageAccount -ResourceGroupName $global:workingResourceGroupName -Name $global:workingStorageAccountName -Force
        Write-Host "created..."
    }
    # New-AzStorageAccount -ResourceGroupName $global:workingResourceGroupName -Name $global:workingStorageAccountName `
    #                           -Kind Storage -Location $global:location -SkuName Standard_LRS

}
Set-AzCurrentStorageAccount -ResourceGroupName $global:workingResourceGroupName -StorageAccountName $global:workingStorageAccountName
Write-Host "Rebuilt..."
$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed to rebuild the storage acount"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

Get-AzStorageContainer -Name $global:workingContainerName
if ($? -eq $false) {
    Write-Host "Setting up storage container $global:workingContainerName"  -ForegroundColor green
    $destKey=Get-AzStorageAccountKey -ResourceGroupName $global:workingResourceGroupName -Name $global:workingStorageAccountName
    $destContext=New-AzStorageContext -StorageAccountName $global:workingStorageAccountName -StorageAccountKey $destKey[0].Value

    New-AzStorageContainer -name $global:workingContainerName -Permission Blob -Context $destContext
    Write-Host "And populated."
}

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed populate the containers"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()
#
#
#  Copy the virtual machines to the staging container
#
get-job | Stop-Job
get-job | Remove-Job
copy_azure_machines
$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed copy the images"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

#
#  Launch the virtual machines
#
get-job | Stop-Job
get-job | Remove-Job
create_azure_topology
write-host "$global:num_remaining machines have been launched.  Waiting for completion..."
$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed create the topology"
$commandTimer = [Diagnostics.Stopwatch]::StartNew()

#
#  Wait for the machines to report back
#
Get-EventSubscriber -SourceIdentifier $timerName | Unregister-Event

Write-Host "                          Initiating temporal evaluation loop (Starting the timer)" -ForegroundColor yellow

Register-ObjectEvent -InputObject $timer -EventName elapsed -SourceIdentifier $timerName -Action $action
$global:timer_is_running=1
$timer.Interval = 1000
$timer.Enabled = $true
$timer.start() > $null

Write-Host "Finished launching the VMs.  Waiting for Completed to go to 1.  Completed is presently $global:completed" -ForegroundColor Yellow
while ($global:completed -eq 0) {
    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Host "                         Exiting Temporal Evaluation Loop (Unregistering the timer)" -ForegroundColor yellow
Write-Host ""
$global:timer_is_running=0
$timer.stop()
Get-EventSubscriber -SourceIdentifier $timerName | Unregister-Event

$commandTimer.Stop()
$elapsed = $commandTimer.Elapsed
Write-Host "It required $elapsed complete the timer loop"

if ($global:num_remaining -eq 0) {
    Write-Host "                          All machines have come back up.  Checking results." -ForegroundColor green
    Write-Host ""

    if ($global:failed -eq $true) {
        Write-Host "     Failures were detected in reboot and/or reporting of kernel version.  See log above for details." -ForegroundColor red
        Write-Host "                                             BORG TESTS HAVE FAILED!!" -ForegroundColor red
    } else {
        Write-Host "     All machines rebooted successfully to some derivitive of kernel version $global:booted_version" -ForegroundColor green
        Write-Host "                                  BORG has been passed successfully!" -ForegroundColor green
    }
} else {
        Write-Host "                              Not all machines booted in the allocated time!" -ForegroundColor red
        Write-Host ""
        Write-Host " Machines states are:" -ForegroundColor red
        foreach ($localMachine in $global:monitoredMachines) {
            [MonitoredMachine]$monitoredMachine=$localMachine
            $monitoredMachineName=$monitoredMachine.name
            $monitoredMachineState=$monitoredMachine.status
            if ($monitoredMachineState -ne "Completed") {

                if ($monitoredMachine.session -ne $null) {
                    Write-Host "   ----- Machine $monitoredMachineName is in state $monitoredMachineState.  This is the log, if any:" -ForegroundColor red
                    $log_lines=invoke-command -session $monitoredMachine.session -ScriptBlock { get-content /opt/microsoft/borg_progress.log } -ErrorAction SilentlyContinue
                    if ($? -eq $true) {
                        $log_lines | write-host -ForegroundColor Magenta
                    }
                } else {
                    Write-Host "      ----- No remote log available.  Either the machine is off-line or the log was not created." -ForegroundColor Red
                }
            } else {
                Write-Host Machine "   ----- Machine $monitoredMachineName is in state $monitoredMachineState" -ForegroundColor green
            }
            $global:failed = 1
        }
    }

Write-Host ""

$overallTimer.Stop()
$elapsed = $overallTimer.Elapsed
Write-Host "It required $elapsed to set up"

Stop-Transcript

if ($global:failed -eq 0) {
    Write-Host "                                    BORG is Exiting with success.  Thanks for Playing" -ForegroundColor green
    exit 0
} else {
    Write-Host "                                    BORG is Exiting with failure.  Thanks for Playing" -ForegroundColor red
    exit 1
}
