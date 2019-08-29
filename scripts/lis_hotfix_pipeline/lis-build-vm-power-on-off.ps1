# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

<#
.Description
    Changes the power state of LIS build VMs.
#>

param(
    # LIS RPM Build VM's resource group.
    [string] $ResourceGroupName,

    # Subscription secret file
    [string] $secretsFile,

    # On/Off
    [string] $Operation,

    # Architecture
    [string] $Arch
)

try {
    Invoke-WebRequest -Uri https://raw.githubusercontent.com/LIS/LISAv2/master/Libraries/TestLogs.psm1 -UseBasicParsing -OutFile ".\TestLogs.psm1"
    Invoke-WebRequest -Uri https://raw.githubusercontent.com/LIS/LISAv2/master/Libraries/TestHelpers.psm1 -UseBasicParsing -OutFile ".\TestHelpers.psm1"
    Import-Module ".\scripts\lis_hotfix_pipeline\Library.psm1" -Force
    Import-Module ".\TestLogs.psm1" -Force
    Import-Module ".\TestHelpers.psm1" -Force

    Set-Variable -Name LogDir -Value ".\" -Scope Global
    Set-Variable -Name LogFileName -Value "lis-build-vm-power-on-off.log.txt" -Scope Global

    Register-AzureSubscription($secretsFile)

    $VMs = Get-AzVm | Where-Object {$_.Name -inotmatch 'controller_vm' -and $_.ResourceGroupName -eq $ResourceGroupName} -Verbose

    # Perform the Power ON/OFF operation
    $Jobs = @()
    foreach ($VM in $VMs) {
        if($VM.Name -inotmatch $Arch) {
            continue
        }
        if ($Operation -imatch "off") {
            Write-LogInfo "Stopping $($VM.Name)..."
            $Jobs += $VM | Stop-AzVm -AsJob -Force
        } elseif ($Operation -imatch "On") {
            Write-LogInfo "Starting $($VM.Name)..."
            $Jobs += $VM | Start-AzVm -AsJob
        } else {
            Write-LogErr "Unsupported VM operation '$Operation'. Supported operations : On/Off"
            exit 1
        }
    }

    $InCompleteJobs = ($Jobs | Where-Object {$_.State -imatch "running"}).Count
    while ($InCompleteJobs -ne 0) {
        Write-LogInfo "'$InCompleteJobs' jobs still running. Waiting 10 seconds..."
        Start-Sleep -Seconds 10
        $InCompleteJobs = ($Jobs | Where-Object {$_.State -imatch "running"}).Count
    }

    # Remove the jobs once completed.
    Write-Host "Removing $($Jobs.Count) completed background jobs..."
    $Jobs | Remove-Job -Force

    # Verify SSH for all VMs...
    if ($Operation -imatch "On") {
        $OfflineVMs = 0
        $Resources = Get-AzResource | Where-Object {$_.ResourceGroupName -eq $ResourceGroupName }
        $LB = $Resources | Where-Object { $_.ResourceType -eq "Microsoft.Network/loadBalancers" }
        $LB = Get-AzLoadBalancer -Name $LB.Name -ResourceGroupName $ResourceGroupName
        $NatRules = $LB.InboundNatRules | Where-Object {$_.BackendIPConfiguration.Id -ne $null }
        $PublicIP = $Resources | Where-Object { $_.ResourceType -eq "Microsoft.Network/publicIPAddresses" }
        $PublicIP = Get-AzPublicIpAddress -Name $PublicIP.Name -ResourceGroupName $ResourceGroupName

        # We're iterating through all VMs without breaking out after detecting 1st offline VM.
        # This is done to print all the VMs which were offline and it helps in debugging.
        foreach ($Rule in $NatRules) {
            if ($Rule.Name -inotmatch $Arch) {
                continue
            }
            if (Test-SSH -PublicIP $PublicIP.IpAddress -SSHPort $Rule.FrontendPort) {
                Write-LogInfo "$($Rule.Name) : VM Online"
            } else {
                Write-LogErr "$($Rule.Name) : VM Offline"
                $OfflineVMs += 1
            }
        }
        if ($OfflineVMs -ne 0) {
            Throw "Unable to proceed due to $OfflineVMs offline VMs."
        }
    }
    Write-LogInfo "All operations completed successfully."
} catch {
    $line = $_.InvocationInfo.ScriptLineNumber
    $script_name = ($_.InvocationInfo.ScriptName).Replace($PWD, ".")
    $ErrorMessage = $_.Exception.Message
    Write-LogInfo "EXCEPTION : $ErrorMessage"
    Write-LogInfo "Source : Line $line in script $script_name."
    exit 1
}
