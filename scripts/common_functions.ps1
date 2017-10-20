function login_azure {
    param (
        [string] $rg = "", 
        [string] $sa = "", 
        [string] $location = "" ,
        [bool] $createOnError = $false)

    . "C:\Framework-Scripts\secrets.ps1"

    Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx' > $null
    Select-AzureRmSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID" > $null

    if ($rg -ne "" -and $sa -ne "") {
        $existingAccount = Get-AzureRmStorageAccount -ResourceGroupName $rg -Name $sa
        if ($? -eq $true) {
            #
            #  Existing account -- use it
            $currentLoc = ($existingAccount.Location).ToString()

            if ($currentLoc -ne $location) {
                if ($false -eq $createOnError) {
                #
                    #  Wrong region and we're suppposed to use existing.  This won't work, but we may not care         
                    Write-Warning "***************************************************************************************"
                    Write-Warning "Storage account $sa is in different region ($currentLoc) than current ($location)."
                    Write-Warning "       You will not be able to create any virtual machines from this account!"
                    Write-Warning "***************************************************************************************"
                    Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $sa
                } else {
                    #
                    #  Take it out and start over
                    Remove-AzureRmStorageAccount -ResourceGroupName $rg -Name $sa -Force
                    New-AzureRmStorageAccount -ResourceGroupName $rg -Name $sa -Kind Storage -Location $location -SkuName Standard_LRS
                    Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $sa
                }
            } else {
                #
                #  Account is present and location is good.  Use this one.
                Write-Verbose "Using existing storage account $sa in resource group $rg"
            }
        } elseif ($false -eq $createOnError) {
            Write-Warning "***************************************************************************************"
            Write-Warning "Storage account $sa does not exist in location $location. and CreateOnError was not set."
            Write-Warning "***************************************************************************************"
            $sa = $null
        } else {
            New-AzureRmStorageAccount -ResourceGroupName $rg -Name $sa -Kind Storage -Location $location -SkuName Standard_LRS 
            Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $sa
        }
    }

    return $sa
}

function make_cred () {
    . "C:\Framework-Scripts\secrets.ps1"

    $pw = convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PASS" 
    $cred = new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$pw

    return $cred
}

function make_cred_initial () {
    . "C:\Framework-Scripts\secrets.ps1"

    $pw = convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PAS2" 
    $cred = new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$pw

    return $cred
}

function create_psrp_session([string] $vmName, [string] $rg, [string] $SA, [string] $location,
                             [System.Management.Automation.PSCredential] $cred,
                             [System.Management.Automation.Remoting.PSSessionOption] $o)
{
    login_azure $rg $sa $location > $null

    $vm_search_string = $vmName  + "*"
    $vm_search_string = $vm_search_string -replace "_","-"

    [int]$attempts = 0
    while ($attempts -lt 5) {
        $attempts = $attempts + 1
        write-verbose "Attempting to locate host by search string $vm_search_string"
        $ipAddress = Get-AzureRmPublicIpAddress -ResourceGroupName $rg | Where-Object -Property Name -Like $vm_search_string

        write-verbose "Got IP Address $($ipAddress.Name), with IP Address $($ipAddress.IpAddress)"

        if ($ipAddress -ne $null) {
            $theAddress = $ipAddress.IpAddress            
            if ($theAddress.ToLower() -eq "not assigned") {
                Write-Error "Machine $vmName does not have an assigned IP address.  Cannot create PSRP session to the machine."
                return $null
            }

            $remoteIP = $ipAddress.IpAddress
            write-verbose "Attempting contact at $remoteIP"
            $existingSession = Get-PSSession -Name $remoteIP -ErrorAction SilentlyContinue
            if ($? -eq $false -or $existingSession -eq $null) {
                $thisSession = new-PSSession -computername $remoteIP -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o -name $remoteIP
                if ($? -eq $false -or $thisSession -eq $null) {
                    Write-error "Contact failed.  This is attempt $attempts of 5.  Will retry in 15 seconds."
                    start-sleep -Seconds 15
                } else {
                    write-verbose "Contact was successful"
                    return $thisSession
                }
            } else {
                write-verbose "Re-using session for $remoteIP"
                return $existingSession
            }
        } else {
            Write-Warning "The public IP for machnine $vmName does appear to exist, but the Magic modules are not loaded.  Cannot process this iteration.."
            start-sleep -Seconds 15
        }
    }
    return $null
}

function stop_machines_in_group([Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine[]] $runningVMs,
                                    [string] $destRG,
                                    [string] $destSA,
                                    [string] $location)
{
    if ($null -eq $runningVMs) {
        Write-Error "Cannot stop empty group"
        return
    }

    Write-Verbose "Removing from $destRG and $destSA"

    $scriptBlockString =
    {
        param ([Parameter(Mandatory=$false)] [string] $vm_name,
                [Parameter(Mandatory=$false)] [string] $destRG,
                [Parameter(Mandatory=$false)] [string] $destSA,
                [Parameter(Mandatory=$false)] [string] $location
        )
                
        . C:\Framework-Scripts\common_functions.ps1
        . C:\Framework-Scripts\secrets.ps1

        login_azure $destRG $destSA $location
        Write-Verbose "Stopping machine $vm_name in RG $destRG"
        Stop-AzureRmVM -Name $vm_name -ResourceGroupName $destRG -Force
    }

    $scriptBlock = [scriptblock]::Create($scriptBlockString)

    foreach ($singleVM in $runningVMs) {
        $vm_name = $singleVM.Name
        $vmJobName = $vm_name + "-Src"
        write-verbose "Starting job to stop VM $vm_name"
        Start-Job -Name $vmJobName -ScriptBlock $scriptBlock -ArgumentList $vm_name,$destRG,$destSA,$location
    }

    $allDone = $false
    while ($allDone -eq $false) {
        $allDone = $true
        foreach ($singleVM in $runningVMs) {
            $vm_name = $singleVM.Name
            $vmJobName = $vm_name + "-Src"
            $job = Get-Job -Name $vmJobName
            $jobState = $job.State
            write-verbose "    Job $vmJobName is in state $jobState"
            if ($jobState -eq "Running") {
                $allDone = $false
            }
        }

        if ($allDone -eq $false) {
            Start-Sleep -Seconds 10
        }
    }
}

function deallocate_machines_in_list([string[]] $requestedNames,
                                    [string] $destRG,
                                    [string] $destSA,
                                    [string] $location)
{
    Write-Verbose "Deprovisioning from $destRG and $destSA"

    if ($null -eq $runningVMs) {
        Write-Error "Cannot deprovision empty group"
        return
    }

    $scriptBlockString =
    {
        param ([Parameter(Mandatory=$false)] [string] $vm_name,
                [Parameter(Mandatory=$false)] [string] $destRG,
                [Parameter(Mandatory=$false)] [string] $destSA,
                [Parameter(Mandatory=$false)] [string] $location
        )
                
        . C:\Framework-Scripts\common_functions.ps1
        . C:\Framework-Scripts\secrets.ps1

        login_azure $destRG $destSA $location
        write-verbose "Deallocating machine $vm_name in RG $destRG"
        Remove-AzureRmVM -Name $vm_name -ResourceGroupName $destRG -Force

        Get-AzureRmNetworkInterface -ResourceGroupName $destRG | Where-Object -Property Name -Like $vm_name | Remove-AzureRmNetworkInterface -Force

        Get-AzureRmPublicIpAddress -ResourceGroupName $destRG | Where-Object -Property Name -Like $vm_name | Remove-AzureRmPublicIpAddress -Force
    }

    if ($runningVMs.Count -lt 1) {
        return
    }

    $scriptBlock = [scriptblock]::Create($scriptBlockString)
    foreach ($vm_name in $requestedNames) {
        $vmJobName = $vm_name + "-Deprov"
        write-verbose "Starting job to deprovision VM by list $vm_name"
        Start-Job -Name $vmJobName -ScriptBlock $scriptBlock -ArgumentList $vm_name,$destRG,$destSA
    }

    $allDone = $false
    while ($allDone -eq $false) {
        $allDone = $true
        $timeNow = get-date
        write-verbose "Checking jobs at time $timeNow :"
        foreach ($vm_name in $requestedNames) {
            $vmJobName = $vm_name + "-Deprov"
            $job = Get-Job -Name $vmJobName
            $jobState = $job.State
            $useColor = "Yellow"
            if ($jobState -eq "Completed") {
                $useColor="green"
            } elseif ($jobState -eq "Failed") {
                $useColor = "Red"
            } elseif ($jobState -eq "Blocked") {
                $useColor = "Magenta"
            }
            write-verbose "    Job $vmJobName is in state $jobState"
            if ($jobState -eq "Running") {
                $allDone = $false
            }
        }

        if ($allDone -eq $false) {
            Start-Sleep -Seconds 10
        }
    }

    if ($allDone -eq $false) {
        Start-Sleep -Seconds 10
    }
}

function stop_machines_in_list([stringe[]] $requestedNames,
                                    [string] $destRG,
                                    [string] $destSA,
                                    [string] $location)
{
    $scriptBlockString =
    {
        param ([Parameter(Mandatory=$false)] [string] $vm_name,
                [Parameter(Mandatory=$false)] [string] $destRG,
                [Parameter(Mandatory=$false)] [string] $destSA,
                [Parameter(Mandatory=$false)] [string] $location
        )
                
        . C:\Framework-Scripts\common_functions.ps1
        . C:\Framework-Scripts\secrets.ps1

        login_azure $destRG $destSA $location
        Write-Verbose "Stopping machine $vm_name in RG $destRG"
        Stop-AzureRmVM -Name $vm_name -ResourceGroupName $destRG -Force
    }

    $scriptBlock = [scriptblock]::Create($scriptBlockString)

    foreach ($vm_name in $requestedNames) {
        $vmJobName = $vm_name + "-Src"
        write-verbose "Starting job to stop VM $vm_name"
        Start-Job -Name $vmJobName -ScriptBlock $scriptBlock -ArgumentList $vm_name,$destRG,$destSA,$location
    }

    $allDone = $false
    while ($allDone -eq $false) {
        $allDone = $true
        foreach ($singleVM in $runningVMs) {
            $vm_name = $singleVM.Name
            $vmJobName = $vm_name + "-Src"
            $job = Get-Job -Name $vmJobName
            $jobState = $job.State
            write-verbose "    Job $vmJobName is in state $jobState"
            if ($jobState -eq "Running") {
                $allDone = $false
            }
        }

        if ($allDone -eq $false) {
            Start-Sleep -Seconds 10
        }
    }
}

function deallocate_machines_in_group([Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine[]]  $runningVMs,
                                    [string] $destRG,
                                    [string] $destSA,
                                    [string] $location)
{
    $scriptBlockString =
    {
        param ([Parameter(Mandatory=$false)] [string] $vm_name,
                [Parameter(Mandatory=$false)] [string] $destRG,
                [Parameter(Mandatory=$false)] [string] $destSA,
                [Parameter(Mandatory=$false)] [string] $location
        )
                
        . C:\Framework-Scripts\common_functions.ps1
        . C:\Framework-Scripts\secrets.ps1

        login_azure $destRG $destSA $location
        Write-verbose "Deallocating machine $vm_name in RG $destRG"
        Remove-AzureRmVM -Name $vm_name -ResourceGroupName $destRG -Force

        Get-AzureRmNetworkInterface -ResourceGroupName $destRG | Where-Object -Property Name -Like $vm_name | Remove-AzureRmNetworkInterface -Force

        Get-AzureRmPublicIpAddress -ResourceGroupName $destRG | Where-Object -Property Name -Like $vm_name | Remove-AzureRmPublicIpAddress -Force
    }

    $scriptBlock = [scriptblock]::Create($scriptBlockString)
    $launchedAJob = $false
    foreach ($singleVM in $runningVMs) {
        $vm_name = $singleVM.Name
        write-verbose "Starting job to deprovision VM $vm_name"
        $vmJobName = $vm_name + "-Deprov"
        Start-Job -Name $vmJobName -ScriptBlock $scriptBlock -ArgumentList $vm_name,$destRG,$destSA
        $launchedAJob = $true
    }

    if ($launchedAJob -eq $true) {
        start-sleep -Seconds 10

        $allDone = $false
        while ($allDone -eq $false) {        
            $allDone = $true
            $timeNow = get-date
            write-verbose "Checking jobs at time $timeNow :" 
            $vm_name = $singleVM.Name
            $vmJobName = $vm_name + "-Deprov"
            $job = Get-Job -Name $vmJobName
            $jobState = $job.State        
            write-verbose "    Job $vmJobName is in state $jobState" 
            if ($jobState -eq "Running") {
                $allDone = $false
            } 

            if ($allDone -eq $false) {
                Start-Sleep -Seconds 10
            }
        }

        if ($allDone -eq $false) {
            Start-Sleep -Seconds 10
        }
    }
}


function try_pscp([string] $file,
                  [string] $ipTemp)
{
    . C:\Framework-Scripts\secrets.ps1
    
    [int]$num_tries = 0
    $result = $false
    $plink_err = $null
    while ($num_tries -lt 10) {
        $num_tries = $num_tries + 1
        try {
            $plink_err = C:\azure-linux-automation\tools\pscp -pw $TEST_USER_ACCOUNT_PAS2 -l $TEST_USER_ACCOUNT_NAME $file $ipTemp 2>&1
            $result = $?
        }
        catch {
                Write-error "pscp Exception caught -- trying again"
        }

        if ($plink_err -ne $null -and $plink_err -match ".*connection timed out*")
        {
            Write-error "Timeout on pscp of $file to $ipTemp"
        } elseif ($result -eq $false) {
            write-error "General error copying file $file to $ipTemp..."
            Write-Output $plink_err
        } else {
            write-verbose "$file Successfully copied to $ipTemp"
            return $plink_err
        }

        start-sleep 12
    }

    Write-Error "FAILURE copying file $file to $ipTemp.  Gave up after 2 minutes"
}

function try_plink([string] $ip,
                   [string] $command)
{
    . C:\Framework-Scripts\secrets.ps1

    $port=22
    
    [int]$num_tries = 0
    $result = $false
    $plink_err = $null
    while ($num_tries -lt 10) {
        $num_tries = $num_tries + 1
        try {
            C:\azure-linux-automation\tools\plink.exe -C -v -pw $TEST_USER_ACCOUNT_PAS2 -P $port -l $TEST_USER_ACCOUNT_NAME $ip $command
            $result = $?
        }
        catch {
                Write-error "plink Exception caught -- trying again"
        }

        if ($result -eq $false -and $num_tries -eq 10) {
            write-verbose "General error executing command.  Returning anyway, because this usually means it ran properly."
            return
        } elseif ($result -eq $false) {
            Write-Verbose "Error on plink call.  Trying again"
        } elseif ($result -eq $true) {
            write-verbose "Successful command execution"
            return
        }
    }
}

#Copy VHD to another storage account
Function CopyVHDToAnotherStorageAccount {
    param (
        [string]$sourceStorageAccount,
        [string]$sourceStorageContainer,
        [string]$sourceRG,
        [string]$destinationStorageAccount,
        [string]$destinationStorageContainer,
        [string]$destRG,
        [string]$vhdName,
        [string]$destVHDName)

    $retValue = $false
    if (!$destVHDName)
    {
        $destVHDName = $vhdName
    }

    Write-Verbose "Retrieving $sourceStorageAccount storage account key"
    $SrcStorageAccountKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $sourceRG -Name $sourceStorageAccount)[0].Value
    [string]$SrcStorageAccount = $sourceStorageAccount
    [string]$SrcStorageBlob = $vhdName
    $SrcStorageContainer = $sourceStorageContainer


    Write-Verbose "Retrieving $destinationStorageAccount storage account key"
    $DestAccountKey= (Get-AzureRmStorageAccountKey -ResourceGroupName $destRG -Name $destinationStorageAccount)[0].Value
    [string]$DestAccountName =  $destinationStorageAccount
    [string]$DestBlob = $destVHDName
    $DestContainer = $destinationStorageContainer

    $context = New-AzureStorageContext -StorageAccountName $srcStorageAccount -StorageAccountKey $srcStorageAccountKey 
    $expireTime = Get-Date
    $expireTime = $expireTime.AddYears(1)
    $SasUrl = New-AzureStorageBlobSASToken -container $srcStorageContainer -Blob $srcStorageBlob -Permission R -ExpiryTime $expireTime -FullUri -Context $Context 

    $destContext = New-AzureStorageContext -StorageAccountName $destAccountName -StorageAccountKey $destAccountKey
    $testContainer = Get-AzureStorageContainer -Name $destContainer -Context $destContext -ErrorAction Ignore
    if ($testContainer -eq $null) 
    {
        $out = New-AzureStorageContainer -Name $destContainer -context $destContext
    }
    # Start the Copy
    Write-Verbose "Copy $vhdName --> $($destContext.StorageAccountName) : Running"
    $out = Start-AzureStorageBlobCopy -AbsoluteUri $SasUrl  -DestContainer $destContainer -DestContext $destContext -DestBlob $destBlob -Force
    #
    # Monitor replication status
    #
    $CopyingInProgress = $true
    while($CopyingInProgress)
    {
        $CopyingInProgress = $false
        $status = Get-AzureStorageBlobCopyState -Container $destContainer -Blob $destBlob -Context $destContext   
        if ($status.Status -ne "Success") 
        {
            $CopyingInProgress = $true
        }
        else
        {
            Write-Verbose "Copy $DestBlob --> $($destContext.StorageAccountName) : Done"
            $retValue = $true

        }
        if ($CopyingInProgress)
        {
            $copyPercentage = [math]::Round( $(($status.BytesCopied * 100 / $status.TotalBytes)) , 2 )
            Write-Verbose "Bytes Copied:$($status.BytesCopied), Total Bytes:$($status.TotalBytes) [ $copyPercentage % ]"            
            Sleep -Seconds 10
        }
    }
    return $retValue
}

function Assert-PathExists {
    param(
        [String] $Path
    )
    if (!(Test-Path $Path)) {
       throw "Path $Path not found."
    }

}

function Assert-URLExists {
    param(
        [String] $URL
    )

    Write-Host "Checking Kernel URL"
    $httpRequest = [System.Net.WebRequest]::Create($URL)
    $httpResponse = $httpRequest.GetResponse()
    $httpStatus = [int]$httpResponse.StatusCode

    if ($httpStatus -ne 200) {
        Write-Host "URL $URL cannot be reached."
        throw "URL $URL cannot be reached."
    }

    $httpResponse.Close()
}

