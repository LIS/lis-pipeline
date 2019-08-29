# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

<#
.Description
    This script creates a LIS RPM BUILD VM in Azure based on incoming Linux distro and Errata kernel.

Important Notes:
================
    1.  This script requires a resource group with below architecture.

    LIS-RPM-BUILD-RESOURCE-GROUP (Name can be anything)
    |--StorageAccount (say lisbuild0001. Should be passed to this script as string parameter)
    |--|--basevhdrepo (This is container. Name is case-sensitive)
    |--|--|--lis_build_centos_73_x64.vhd (This VHD should be present in container with exact name.)
    |--|--|--lis_build_centos_74_x64.vhd (This VHD should be present in container with exact name.)
    |--|--|--lis_build_centos_75_x64.vhd (This VHD should be present in container with exact name.)
    |--|--|--lis_build_centos_76_x64.vhd (This VHD should be present in container with exact name.)
    |--|--kernel (This is container. Name is case-sensitive)
    |--|--|--<kernel-version-1> (This is folder)
    |--|--|--|--<kernel-version-1>.rpm
    |--|--|--|--<kernel-version-1>-devel.rpm
    |--|--|--<kernel-version-2> (This is folder)
    |--|--|--|--<kernel-version-2>.rpm
    |--|--|--|--<kernel-version-2>-devel.rpm
    |--StorageAccount (say lisbuildbootdiag. Should be passed to this script as string parameter)

    And, Other common resources, as follows:
    |--AvailiblitySet
    |--VirtualNetwork
    |--LoadBalancer
    |--PublicIP

#>
param (
    $DistroKernelVersions = "",
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
    Write-LogInfo "Get-AzStorageAccount ..."
    $storageAccounts = Get-AzStorageAccount
    $storageAccount = $storageAccounts | Where-Object { $_.StorageAccountName -eq $VHDSourceStorageAccount }
    $ResourceGroupName = $storageAccount.ResourceGroupName
    $Location = $storageAccount.Location
    Write-LogInfo "Get-AzStorageAccountKey -ResourceGroupName $($storageAccount.ResourceGroupName) -Name $($storageAccount.StorageAccountName)..."
    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName)[0].Value
    $context = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageKey

    #Set Global Variables.
    Set-Variable -Name ResourceGroupName -Value $ResourceGroupName -Scope Global
    Set-Variable -Name Location -Value $Location -Scope Global
    Set-Variable -Name BootDiagnosticStorageAccount -Value $BootDiagnosticStorageAccount -Scope Global
    Set-Variable -Name context -Value $context -Scope Global

    Write-LogInfo "Get-AzStorageContainer..."
    $allDiskNames = @()
    $VHDCopyOperations = @()
    $SourceContainer = "basevhdrepo"
    $container = Get-AzStorageContainer -Context $context -ConcurrentTaskCount 64 | Where-Object { $_.Name -eq $SourceContainer }
    $TotalKernels = $DistroKernelVersions.split(",").Count

    Write-LogInfo "Get-AzStorageBlob -Container $($container.Name) ..."
    $blobs = Get-AzStorageBlob -Container $container.Name -Context $context
    foreach ($blob in $blobs) {
        $DiskURI = $($blob.ICloudBlob.Uri.AbsoluteUri)
        $allDiskNames += $DiskURI.Split()
    }
    $AllVMs = (Get-AzVM -ResourceGroupName $ResourceGroupName).Name
    foreach ($item in $DistroKernelVersions.split(",")) {
        $RequestedDistro = $item.split("=")[0].Replace("rhel_", "").Replace("centos_", "").Replace(".", "")
        Write-LogInfo "Requested distro = $RequestedDistro"
        $matchedDistros = $AllVMs | Where-Object { $_ -imatch "_$RequestedDistro`_" }
        $matchedDistrosURL = $allDiskNames | Where-Object { $_ -imatch "_$RequestedDistro`_" }
        if ($matchedDistros.count -gt 0 ) {
            $BaseVHD = $matchedDistrosURL | Where-Object { $_ -inotmatch "update" }
            $DestVHD = $BaseVHD.Replace(".vhd", "_update$($matchedDistros.count).vhd")
            Write-LogInfo "$BaseVHD-->$DestVHD"
            $VHDCopyOperations += Start-VHDCopy -context $context -source $BaseVHD.Split("/")[-1] -destination $DestVHD.Split("/")[-1] -Container $SourceContainer
        }
    }

    if ( -not $VHDCopyOperations) {
        Throw "Unable to copy the VHDs. Exiting with 1."
    }

    # Poll and wait till VHD copy.
    Test-VHDCopyOperations -VHDCopyOperations $VHDCopyOperations -context $context -Container $SourceContainer
    $blobs = Get-AzStorageBlob -Container $container.Name -Context $context
    # Create a new VM for each copied VHD.
    $CreatedVMs = @()
    foreach ($operation in $VHDCopyOperations) {
        $blob = $blobs | Where-Object { $_.ICloudBlob.Uri.AbsoluteUri -eq $operation.ICloudBlob.Uri.AbsoluteUri }
        $OSDiskConfig = New-AzDiskConfig -AccountType Standard_LRS `
            -Location $storageAccount.Location -CreateOption Import `
            -SourceUri $operation.ICloudBlob.Uri.AbsoluteUri -OsType Linux
        $osDiskName = "$($operation.Name)-OsDisk"
        $osDiskName = $osDiskName.Replace(' ', '_')
        $VMName = $($operation.Name).TrimEnd(".vhd")
        $VMName = $VMName.Replace(' ', '_')
        $Retry = $true
        While ($Retry) {
            try {
                Write-LogInfo "Converting $($operation.ICloudBlob.Uri.AbsoluteUri) to managed disk (CreateOption: Import)"
                $ManagedDisk = New-AzDisk -DiskName $osDiskName -Disk $OSDiskConfig -ResourceGroupName $storageAccount.ResourceGroupName -Verbose
                if (-not $?) {
                    Throw "Disk Creation Failed. Retrying..."
                } else {
                    $null = $blob | Remove-AzStorageBlob -Force -Verbose
                    if ($?) {
                        Write-LogInfo "$($blob.ICloudBlob.Uri.AbsoluteUri) deleted successfully."
                    } else {
                        Write-LogErr "$($blob.ICloudBlob.Uri.AbsoluteUri) failed to delete. Please cleanup manually."
                    }
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
    if ($CreatedVMs) {
        if ($CreatedVMs.Count -eq $TotalKernels) {
            $PublicIP = Get-AzPublicIpAddress | Where-Object { $_.ResourceGroupName -eq "$ResourceGroupName" }
            $PublicIPAddress = $PublicIP.IpAddress
            $Resources = Get-AzResource -ResourceGroupName $ResourceGroupName
            $LB = $Resources | Where-Object { $_.ResourceType -eq "Microsoft.Network/loadBalancers" }
            foreach ($item in $DistroKernelVersions.split(",")) {
                $RequestedDistro = $item.split("=")[0].Replace("rhel_", "").Replace("centos_", "").Replace(".", "")
                $RequestedKernel = $item.split("=")[1]
                $VMName = $CreatedVMs | Where-Object { $_ -imatch "_$RequestedDistro`_" }
                $NatRuleName = "$VMName-SSH"
                $Packages = Get-RPMPackageNames -StorageContext $context -FolderPath kernel -KernelVersion $RequestedKernel
                Write-LogInfo "Checking SSH Rule $NatRuleName ..."
                $LB2 = Get-AzLoadBalancer -Name $LB.Name -ResourceGroupName $ResourceGroupName
                $NatRule = Get-AzLoadBalancerInboundNatRuleConfig -LoadBalancer $LB2 -Name $NatRuleName
                $SSHPort = $NatRule.FrontendPort
                $KernelInstallStatus = Install-KernelPackages -PublicIP $PublicIPAddress -SSHPort $SSHPort -KernelPackage $Packages[0] `
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
            $RequestedDistro = $item.split("=")[0].Replace("rhel_", "").Replace("centos_", "").Replace(".", "")
            $RequestedKernel = $item.split("=")[1]
            $VMName = $CreatedVMs | Where-Object { $_ -imatch "_$RequestedDistro`_" }
            $NatRuleName = "$VMName-SSH"
            $OsDiskName = $VMName + ".vhd-OsDisk"
            $NICName = $VMName + "-NIC"
            Start-FailureCleanup -ResourceGroupName $ResourceGroupName -VMName $VMName -OSDIskName $OsDiskName -NicName $NICName -NatRuleName $NatRuleName
        }
        exit 1
    }
} catch {
    Write-LogErr "Exception in Create Build Machines. Exiting with 1"
    $line = $_.InvocationInfo.ScriptLineNumber
    $script_name = ($_.InvocationInfo.ScriptName).Replace($PWD, ".")
    $ErrorMessage = $_.Exception.Message
    Write-LogInfo "EXCEPTION : $ErrorMessage"
    Write-LogInfo "Source : Line $line in script $script_name."
    exit 1
}