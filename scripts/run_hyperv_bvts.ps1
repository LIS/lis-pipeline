param (
    [Parameter(Mandatory=$false)] [string] $LisaPath="C:\lis-test\WS2012R2\lisa",
    [Parameter(Mandatory=$false)] [string] $VMNames="Unknown",
    [Parameter(Mandatory=$false)] [string] $TestXml="bvt_tests.xml",
    [Parameter(Mandatory=$false)] [string] $LogDir="TestResults",
    [Parameter(Mandatory=$false)] [int] $VMCheckTimeout = 30
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

function Cleanup-Environment () {
    param($VMNames, $LisaPath)
    Write-Host "Cleaning environment before starting LISA..."
    Write-Host "Cleaning up sentinel files..."
    $completedBootsPath = "C:\temp\completed_boots"
    if (Test-Path $LogDir) {
        Remove-Item -ErrorAction SilentlyContinue "$LogDir\*"
    }
    foreach ($vmName in $VMNames) {
        Remove-Item -Path "$LisaPath/$vmName.xml" -Force `
                    -ErrorAction SilentlyContinue
    }
    Get-Job | Stop-Job | Out-Null
    Get-Job | Remove-Job | Out-Null
    Write-Host "Environment has been cleaned."
}

function Get-StartLISAScript () {
    $scriptBlock = {
        param($VMName, $LisaPath, $TestXml, $LogDir)
        [xml]$xmlContents = Get-Content -Path $TestXml
        $xmlContents.config.Vms.vm.vmName = "${VMName}"
        $newXmlPath = "$LisaPath\$vmName.xml" 
        $xmlContents.save($newXmlPath)
        & "$LisaPath/lisa.ps1" run $newXmlPath -CliLogDir $LogDir
        if (-not $?) {
            throw "lisa failed to start"
        }
    }
    return $scriptBlock
}

Workflow Start-LISAJobs () {
    param($VMNames, $LisaPath, $TestXml, $LogDir, $VMCheckTimeout)
    InlineScript {
        Write-Host "Running LISA..."
    }
    $errors = 0
    $suffix = Get-Random 1000000
    $scriptBlock = $null
    $vmTested = @()
    foreach -parallel ($vmName in $VMNames) {
        $Workflow:scriptBlock = Get-StartLISAScript
        try {
            if (!$Workflow:scriptBlock) {
                Start-Sleep 1
            }
            if (!$Workflow:scriptBlock) {
                throw "Failure in PowerShell language."
            }
            CreateWait-JobFromScript -ScriptBlock $Workflow:scriptBlock `
                -ArgumentList @($vmName, $LisaPath, $TestXml, $LogDir) `
                -Timeout $VMCheckTimeout -JobName "Start-$vmName-$suffix-{0}"
            $Workflow:vmTested += $vmName
        } catch {
            $Workflow:errors += 1
        }
    }
    if ($Workflow:errors) {
        throw "Starting LISA jobs failed."
    }
    InlineScript {
        Write-Host "Finished LISA starting jobs state."
    }
}

function Main () {
    
    if (-not (Test-Path $LisaPath)) {
        Write-Host "Invalid path $LisaPath for lisa folder." -ForegroundColor Red
        exit 1
    } 
    if (Test-Path $VMNames) {
        $vmNames = Get-Content $VMNames
    } else {
        Write-Host "Invalid path $VMNames for VMNames file." -ForegroundColor Red
        exit 1
    }

    Cleanup-Environment $vmNames $LisaPath
    Start-LISAJobs $vmNames $LisaPath $TestXml $LogDir $VMCheckTimeout
}

Main
