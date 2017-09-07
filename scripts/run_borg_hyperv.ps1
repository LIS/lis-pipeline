#
#  Run the Basic Operations and Readiness Gateway in Hyper-V.  This script will:
#      - Cleans up any existing VM based on the VHD names
#      - Copy all VHDs from the BaseVHDsPath to WorkingVHDsPath
#      - Create and start in parallel a VM for each VHD. It is assumed that the VHD has a
#        properly configured RunOnce set up
#      - Wait for the VMs to tell us it's done.  The VMs will use PSRP to do a live
#        update of a log file on this machine, and will write a sentinel file
#        when the install succeeds or fails.
#
#  Author: John W. Fawcett, Principal Software Development Engineer, Microsoft
#  Author: Adrian Vladu, Senior Cloud Engineer, Cloudbase Solutions SRL
#

param (
    [Parameter(Mandatory=$false)]
    [string] $BaseVHDsPath="D:\azure_images\",
    [Parameter(Mandatory=$false)]
    [string] $WorkingVHDsPath="D:\working_images\",
    [Parameter(Mandatory=$false)]
    [string] $BootResultsPath="c:\temp\boot_results\",
    [Parameter(Mandatory=$false)]
    [string] $ProgressLogsPath="c:\temp\progress_logs\",
    [Parameter(Mandatory=$false)]
    [switch] $UseChildrenVHD,
    [Parameter(Mandatory=$false)]
    [switch] $SkipCopy,
    [Parameter(Mandatory=$false)]
    [int] $VHDCopyTimeout=200,
    [Parameter(Mandatory=$false)]
    [int] $VMCleanTimeout=20,
    [Parameter(Mandatory=$false)]
    [int] $VMBootTimeout=20,
    [Parameter(Mandatory=$false)]
    [int] $VMCheckTimeout=30,
    [Parameter(Mandatory=$false)]
    [string] $VMNamesDumpFilePath="vm-names.txt",
    [Parameter(Mandatory=$false)]
    [string] $KernelVersion="3.10.0-693.1.1.el7.x86_64"
)

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$env:scriptPath = $scriptPath
. "$scriptPath\common_functions.ps1"
. "$scriptPath\backend.ps1"

function CreateWait-JobFromScript {
    param(
        [Parameter(Mandatory=$true)]
        [String] $ScriptBlock,
        [Parameter(Mandatory=$true)]
        [int] $Timeout = 100,
        [Parameter(Mandatory=$false)]
        [array] $ArgumentList,
        [Parameter(Mandatory=$false)]
        [string] $JobName="Hyperv-Borg-Job-{0}",
        [Parameter(Mandatory=$false)]
        [string]$ScriptPath=$env:scriptPath
    )
    $JobName = $JobName -f @(Get-Random 1000000)
    try {
        $initScript = '. "{0}"' -f @("$scriptPath\backend.ps1")
        $s = [Scriptblock]::Create($ScriptBlock)
        $job = Start-Job -Name $JobName -ScriptBlock $s `
            -ArgumentList $ArgumentList `
            -InitializationScript ([Scriptblock]::Create($initScript))
        $jobResult = Wait-Job $job -Timeout $Timeout -Force
        Stop-Job $JobName -ErrorAction SilentlyContinue -Confirm:$false
        $output = Receive-Job $JobName -Keep
        if ($jobResult.State -ne "Completed") {
            Write-Output "Job $JobName failed with output >>`r`n $output`r`n <<"
            throw "Job $JobName failed with output >> $output <<"
        } else {
            Write-Output "Job $JobName succeeded with output >>`r`n $output`r`n <<"
        }
    } catch {
        if (!($PSItem -like "Job $JobName failed with output*")) {
            Write-Output "Job $JobName failed with error: >> `r`n$PSItem`r`n <<"
        }
        throw
    } finally {
        Remove-Job $JobName -ErrorAction SilentlyContinue
    }
}

function Cleanup-Environment {
    Write-Host "Cleaning environment before starting BORG..."
    Write-Host "Cleaning up sentinel files..." -ForegroundColor Green
    $completedBootsPath = "C:\temp\completed_boots"
    if (Test-Path $completedBootsPath) {
        Remove-Item -ErrorAction SilentlyContinue "$completedBootsPath\*"
    }
    if (Test-Path $BootResultsPath) {
        Remove-Item -ErrorAction SilentlyContinue "$BootResultsPath\*"
    }
    if (Test-Path $ProgressLogsPath) {
        Remove-Item -ErrorAction SilentlyContinue "$ProgressLogsPath\*"
    }
    Get-Job | Stop-Job | Out-Null
    Get-Job | Remove-Job | Out-Null
    Write-Host "Environment has been cleaned."
}

function Get-VMNames {
    $vhdsFiles = Get-ChildItem "$BaseVHDsPath\*.vhd*" `
        -ErrorAction SilentlyContinue
    $vmNames = @()
    foreach ($vhdFile in $vhdsFiles) {
         $vmNames += $vhdFile.Name.Split('.')[0]
    }
    return $vmNames
}

function Get-CleanupVMSScript {
    $scriptBlock = {
        param($VMName, $Backend)
        $instance = [HypervBackend]::Deserialize($Backend).GetInstanceWrapper($VMName)
        $instance.Cleanup()
    }
    return $scriptBlock
}

Workflow Cleanup-VMS {
    param($VMNames, $VMCleanTimeout, $Backend)

    Write-Output "Cleaning VMs..."
    $errors = 0
    $suffix = Get-Random 1000000
    $scriptBlock = $null
    foreach -parallel ($vmName in $VMNames) {
        $Workflow:scriptBlock = Get-CleanupVMSScript
        try {
            CreateWait-JobFromScript -ScriptBlock $Workflow:scriptBlock `
                -ArgumentList @($vmName,$Backend) -Timeout $VMCleanTimeout `
                -JobName "DeallocateVM-$vmName-$suffix-{0}" `
                -ScriptPath $env:scriptPath
        } catch {
            $Workflow:errors += 1
        }
    }
    if ($Workflow:errors) {
        throw "VMs cleanup failed."
    }
    (InlineScript {Write-Host "VMs have been cleaned." -ForegroundColor Green})
}

function Get-ScriptBlockVHDS {
     $scriptBlock = {
        param($VHDFile,
              $BaseVHDsPath,
              $WorkingVHDsPath,
              $UseChildrenVHD
        )
        $from = Join-Path $BaseVHDsPath $vhdFile
        $to = Join-Path $WorkingVHDsPath $vhdFile
        Remove-Item -Path $to -Force -ErrorAction SilentlyContinue | Out-Null
        if (!$UseChildrenVHD) {
            Write-Output "Starting to copy VHD $VHDFile to working directory..."
            $out = Robocopy.exe $BaseVHDsPath $WorkingVHDsPath $VHDFile
            if (!(Test-Path $to)) {
                throw ("$VHDFile could not be copied. Robocopy output: $out." + `
                       "LASTEXITCODE: $LASTEXITCODE")
            } else {
                Write-Output "Finished copying $VHDFile to working directory."
            }
        } else {
            New-VHD -ParentPath $from -Path $to | Out-Null
            Write-Output "Finished creating child vhd: $VHDFile in the working directory."
        }
    }.ToString()
    return $scriptBlock
}

Workflow Copy-VHDS {
    param($BaseVHDsPath, $WorkingVHDsPath, $UseChildrenVHD, $VHDCopyTimeout)
    Write-Output "Copying VHDs..."
    $errors = 0
    $suffix = Get-Random 1000000
    $vhdsFiles = Get-ChildItem "$BaseVHDsPath\*.vhd*" -ErrorAction SilentlyContinue
    $scriptBlock = $null
    foreach -parallel ($vhdFile in $vhdsFiles) {
        $Workflow:scriptBlock = Get-ScriptBlockVHDS
        $VHDFileName = $vhdFile.Name
        try {
            CreateWait-JobFromScript -ScriptBlock $Workflow:scriptBlock `
                -ArgumentList @($VHDFileName, $BaseVHDsPath, $WorkingVHDsPath, $UseChildrenVHD) `
                -Timeout $VHDCopyTimeout -JobName "CopyVHD-$VHDFileName-$suffix-{0}" `
                -ScriptPath $env:scriptPath
        } catch {
            $Workflow:errors += 1
        }
    }
    if ($Workflow:errors) {
        throw "Copying VHDS failed."
    }
    (InlineScript {Write-Host "VHDs have been copied."  -ForegroundColor Green})
}

Workflow Create-VMS {
    param($WorkingVHDsPath, $VMBootTimeout, $VMNamesDumpFilePath)
    Write-Output "Creating VMs..."
    $errors = 0
    $suffix = Get-Random 1000000
    $vhdsFiles = Get-ChildItem "$WorkingVHDsPath\*.vhd*" -ErrorAction SilentlyContinue
    $scriptBlock = $null
    $vmsCreated = @()
    foreach -parallel ($vhdFile in $vhdsFiles) {
        $vmName = $vhdFile.Name.Split('.')[0]
        $Workflow:scriptBlock = {
            param($VMName, $VHDPath)
            New-VM -Name $VMName -MemoryStartupBytes 2048MB -Generation 1 `
                -SwitchName "External" -VHDPath $VHDPath | Out-Null
            Set-VM -ProcessorCount 2 -Name $VMName -DynamicMemory:$false
            Set-VMMemory -DynamicMemoryEnabled $false -VMName $VMName
            Enable-VMIntegrationService -Name "*" -VMName $VMName
            Start-VM -Name $VMName
            Write-Output "VM $VMName has been created and started successfully."
        }
        try {
            CreateWait-JobFromScript -ScriptBlock $Workflow:scriptBlock `
                -ArgumentList @($vmName, $vhdFile.FullName) `
                -Timeout $VMBootTimeout -JobName "CreateVM-$vmName-$suffix-{0}" `
                -ScriptPath $env:scriptPath
            $Workflow:vmsCreated += $vmName
        } catch {
            $Workflow:errors += 1
        }
    }
    if ($Workflow:errors) {
        throw "VMs creation failed."
    }
    InlineScript {
        Write-Host ("VMs successfully created: {0}" -f @(($USING:vmsCreated -join ",")))
        Out-File -FilePath (Join-Path $USING:WorkingVHDsPath $USING:VMNamesDumpFilePath) `
                 -Encoding "ASCII" -Force -InputObject ($USING:vmsCreated -join "`r`n")
    }
}

function Get-ScriptblockCheckVMS {
    return  {
        param($VMName, $Credential, $KernelVersion)
        # (avladu): add a retry method
        while ($true) {
            try {
                $ipv4Ip = $null
                $vm = Get-VM -Name $VMName
                $vmNetAdapter = Get-VMNetworkAdapter -VM $vm
                Write-Output "Checking if VM $VMName exposes the IPv4 address...`r`n"
                foreach ($ip in $vmNetAdapter.IPAddresses) {
                    if (([ipaddress]$ip).AddressFamily -eq "InterNetwork") {
                        $ipv4Ip = $ip
                        break
                    }
                }
                if (!$ipv4Ip) {
                    Write-Output "VM $VMName does not expose the IPv4 address yet. Retrying...`r`n"
                    Start-Sleep 5
                    continue
                }
            } catch {
                Write-Output $_.Message
            }
            Write-Output "VM $VMName has been created and started successfully with ip $ip."
            $session = New-PSSession -ComputerName $ipv4Ip -Authentication Basic -Credential $Credential
            $kernel = Invoke-Command -ScriptBlock {uname -r} -Session $session
            $session | Remove-PSSession
            # (avladu): add a retry check here, in case the kernel is getting installed
            if ($KernelVersion -ne $kernel) {
                throw "Kernel versions do not match. Existent kernel $kernel != Desired kernel $KernelVersion"
            } else {
                Write-Output "Kernel versions match. Existent kernel $kernel == Desired kernel`r`n"
            }
            break
        }
    }.ToString()
}

Workflow Check-VMS {
    param($VMNames, $VMCheckTimeout, $creds, $KernelVersion)
    InlineScript {
        Write-Host "Checking VMs state..."
    }
    $errors = 0
    $suffix = Get-Random 1000000
    $scriptBlock = $null
    $vmsCreated = @()
    foreach -parallel ($vmName in $VMNames) {
        $Workflow:scriptBlock = Get-ScriptblockCheckVMS
        try {
            CreateWait-JobFromScript -ScriptBlock $Workflow:scriptBlock `
                -ArgumentList @($vmName, $creds, $KernelVersion) `
                -Timeout $VMCheckTimeout -JobName "CheckVM-$vmName-$suffix-{0}" `
                -ScriptPath $env:scriptPath
            $Workflow:vmsCreated += $vmName
        } catch {
            $Workflow:errors += 1
        }
    }
    if ($Workflow:errors) {
        throw "VMs checks failed."
    }
    InlineScript {
        Write-Host "Finished checking VMs state."
    }
}

function Main {
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
    Write-Host "   "
    Write-Host "                                BORG CUBE is initialized"                   -ForegroundColor Yellow
    Write-Host "              Starting the Dedicated Remote Nodes of Execution (DRONES)" -ForegroundColor yellow
    Write-Host "    "

    Cleanup-Environment $BootResultsPath $ProgressLogsPath
    $vmNames = Get-VMNames
    $Backend = [HypervBackend]::new(@("localhost"))
    Cleanup-VMS -VMNames $vmNames $VMCleanTimeout $Backend.Serialize()

    if (!$SkipCopy) {
        Copy-VHDS $BaseVHDsPath $WorkingVHDsPath $UseChildrenVHD $VHDCopyTimeout
    } else {
        Write-Host "Skipping VHDs copy."
    }

    Create-VMS $WorkingVHDsPath $VMBootTimeout $VMNamesDumpFilePath
    Check-VMS $vmNames $VMCheckTimeout (make_cred) $KernelVersion
}

Main
