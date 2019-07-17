param (
    $DistroKernelVersions="",
    $VHDSourceStorageAccount = "",
    $BootDiagnosticStorageAccount = "",
    $secretsFile = "",
    $LinuxUsername = "",
    $LinuxPassword = ""
)

# Prerequisites to execute LISAv2 functions.
try {
    Invoke-WebRequest -Uri https://raw.githubusercontent.com/LIS/LISAv2/master/Libraries/TestLogs.psm1 -UseBasicParsing -OutFile ".\TestLogs.psm1"
    Invoke-WebRequest -Uri https://raw.githubusercontent.com/LIS/LISAv2/master/Libraries/TestHelpers.psm1 -UseBasicParsing -OutFile ".\TestHelpers.psm1"
    Import-Module ".\scripts\lis_hotfix_pipeline\Library.psm1" -Force
    Import-Module ".\TestLogs.psm1" -Force
    Import-Module ".\TestHelpers.psm1" -Force
    Mkdir .\Tools -ErrorAction SilentlyContinue

    Set-Variable -Name LogDir -Value ".\" -Scope Global
    Set-Variable -Name LogFileName -Value "CreateBuildVMs.log.txt" -Scope Global

    Get-LISAv2Tools -XMLSecretFile $secretsFile

    Register-AzureSubscription($secretsFile)

    # Get required info about LIS Build RPM resource group.
    Write-LogInfo "Get-AzureRmStorageAccount ..."
    $storageAccounts = Get-AzureRmStorageAccount
    $storageAccount = $storageAccounts | Where-Object { $_.StorageAccountName -eq $VHDSourceStorageAccount }
    $ResourceGroupName = $storageAccount.ResourceGroupName
    $Location = $storageAccount.Location
    Write-LogInfo "Get-AzStorageAccountKey -ResourceGroupName $($storageAccount.ResourceGroupName) -Name $($storageAccount.StorageAccountName)..."
    $storageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName)[0].Value
    $context = New-AzureStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageKey

    #Set Global Variables.
    Set-Variable -Name ResourceGroupName -Value $ResourceGroupName -Scope Global
    Set-Variable -Name Location -Value $Location -Scope Global
    Set-Variable -Name BootDiagnosticSourceStorageAccount -Value $BootDiagnosticSourceStorageAccount -Scope Global
    Set-Variable -Name context -Value $context -Scope Global

    Write-LogInfo "Get-AzStorageContainer..."
    $allDiskNames = @()
    $VHDCopyOperations = @()
    $SourceContainer = "vhdsrepo"
    $container = Get-AzureStorageContainer -Context $context -ConcurrentTaskCount 64 | Where-Object { $_.Name -eq $SourceContainer}
    $TotalKernels = $DistroKernelVersions.split(",").Count

    Write-LogInfo "Get-AzStorageBlob -Container $($container.Name) ..."
    $blobs = Get-AzureStorageBlob -Container $container.Name -Context $context
    foreach ($blob in $blobs) {
        $DiskURI = $($blob.ICloudBlob.Uri.AbsoluteUri)
        $allDiskNames += $DiskURI.Split()
    }
    $AllVMs = (Get-AzureRmVM -ResourceGroupName $ResourceGroupName).Name
    foreach ($item in $DistroKernelVersions.split(",")) {
        $RequestedDistro = $item.split("=")[0].Replace("rhel_","").Replace("centos_","").Replace(".","")
        Write-LogInfo "Requested distro = $RequestedDistro"
        $matchedDistros = $AllVMs | Where-Object { $_ -imatch "_$RequestedDistro`_" }
        $matchedDistrosURL = $allDiskNames | Where-Object { $_ -imatch "_$RequestedDistro`_" }
        if ($matchedDistros.count -gt 0 ) {
            $BaseVHD = $matchedDistrosURL | Where-Object { $_ -inotmatch "update"  }
            $DestVHD = $BaseVHD.Replace(".vhd","_update$($matchedDistros.count).vhd")
            Write-LogInfo "$BaseVHD-->$DestVHD"
            $VHDCopyOperations += Start-VHDCopy -context $context -source $BaseVHD.Split("/")[-1] -destination $DestVHD.Split("/")[-1] -Container $SourceContainer
        }
    }

    if ( -not $VHDCopyOperations) {
        Throw "Unable to copy the VHDs. Exiting with 1."
    }

    # Poll and wait till VHD copy.
    Test-VHDCopyOperations -VHDCopyOperations $VHDCopyOperations -context $context -Container $SourceContainer
    # Create a new VM for each copied VHD.
    $CreatedVMs = @()
    foreach ($operation in $VHDCopyOperations) {
        $OSDiskConfig = New-AzureRmDiskConfig -AccountType Standard_LRS  `
            -Location $storageAccount.Location -CreateOption Import `
            -SourceUri $operation.ICloudBlob.Uri.AbsoluteUri -OsType Linux
        $osDiskName =  "$($operation.Name)-OsDisk"
        $osDiskName = $osDiskName.Replace(' ','_')
        $VMName = $($operation.Name).TrimEnd(".vhd")
        $VMName = $VMName.Replace(' ','_')
        $Retry= $true
        While ($Retry) {
            try {
                $ManagedDisk = New-AzureRmDisk -DiskName $osDiskName -Disk $OSDiskConfig -ResourceGroupName $storageAccount.ResourceGroupName -Verbose
                if (-not $?) {
                    Throw "Disk Creation Failed. Retrying..."
                } else {
                    $CreatedVMs += Create-VirtualMachine -Name $VMName -OSDiskID $ManagedDisk.id
                }
                $Retry = $false
            } catch {
                $Retry = $true
                Start-Sleep -Seconds 10 -Verbose
            }
        }
    }

    $SuccessfulKernelInstall = 0
    if ($CreatedVMs){
        if ($CreatedVMs.Count -eq $TotalKernels) {
            $PublicIP = Get-AzureRmPublicIpAddress | Where-Object {$_.ResourceGroupName -eq "$ResourceGroupName"}
            $PublicIPAddress = $PublicIP.IpAddress
            $Resources = Get-AzureRmResource -ResourceGroupName $ResourceGroupName
            $LB = $Resources | Where-Object {$_.ResourceType -eq "Microsoft.Network/loadBalancers"}
            foreach ($item in $DistroKernelVersions.split(",")) {
                $RequestedDistro = $item.split("=")[0].Replace("rhel_","").Replace("centos_","").Replace(".","")
                $RequestedKernel = $item.split("=")[1]
                $VMName = $CreatedVMs | Where-Object {$_ -imatch "_$RequestedDistro`_"}
                $NatRuleName = "$VMName-SSH"
                $Packages = Get-RPMPackageNames -StorageContext $context -FolderPath kernel -KernelVersion $RequestedKernel
                Write-LogInfo "Checking SSH Rule $NatRuleName ..."
                $LB2 = Get-AzureRmLoadBalancer -Name $LB.Name -ResourceGroupName $ResourceGroupName
                $NatRule = Get-AzureRmLoadBalancerInboundNatRuleConfig -LoadBalancer $LB2 -Name $NatRuleName
                $SSHPort = $NatRule.FrontendPort
                $KernelInstallStatus  = Install-KernelPackages -PublicIP $PublicIPAddress -SSHPort $SSHPort -KernelPackage $Packages[0] `
                    -OtherPackages $Packages[1] -LinuxUsername $LinuxUsername -LinuxPassword $LinuxPassword
                if (-not $KernelInstallStatus) {
                    Write-LogInfo "$VMName : $RequestedKernel Kernel install failed. VM will be removed..."
                } else {
                    $SuccessfulKernelInstall += 1
                }
            }
        } else {
            Write-LogInfo "Error: Unable to create $($TotalKernels - $CreatedVMs.Count) VM(s)."
        }
    } else {
        Write-LogInfo "Error: Failed to create VMs."
    }

    if ($SuccessfulKernelInstall -eq $TotalKernels) {
        Write-LogInfo "All Operations completed successfully."
        exit 0
    } else {
        Write-LogInfo "Detected failures. Restoring the build environment to last working condition."
        foreach ($item in $DistroKernelVersions.split(",")) {
            $RequestedDistro = $item.split("=")[0].Replace("rhel_","").Replace("centos_","").Replace(".","")
            $RequestedKernel = $item.split("=")[1]
            $VMName = $CreatedVMs | Where-Object {$_ -imatch "_$RequestedDistro`_"}
            $NatRuleName = "$VMName-SSH"
            $OsDiskName = $VMName + ".vhd-OsDisk"
            $NICName = $VMName + "-NIC"
            Start-FailureCleanup -ResourceGroupName $ResourceGroupName -VMName $VMName -OSDIskName $OsDiskName -NicName $NICName -NatRuleName $NatRuleName
        }
        exit 1
    }
}
catch {
    Write-LogErr "Exception in Create Build Machines. Exiting with 1"
    $line = $_.InvocationInfo.ScriptLineNumber
    $script_name = ($_.InvocationInfo.ScriptName).Replace($PWD,".")
    $ErrorMessage =  $_.Exception.Message
    Write-LogInfo "EXCEPTION : $ErrorMessage"
    Write-LogInfo "Source : Line $line in script $script_name."
    exit 1
}