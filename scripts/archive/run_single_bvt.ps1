param (
    [Parameter(Mandatory=$true)] [string] $sourceName="Unknown",
    [Parameter(Mandatory=$true)] [string] $configFileName="Unknown",
    [Parameter(Mandatory=$true)] [string] $distro="Smoke-BVT",
    [Parameter(Mandatory=$true)] [string[]] $testCycles="BVT"
)

$sourceName = $sourceName.Trim()
$configFileName = $configFileName.Trim()
$distro = $distro.Trim()
$testCycles = $testCycles.Trim()

$logFileName = "c:\temp\transcripts\run_single_bvt-" + $sourceName + "-" + (get-date -format s).replace(":","-")
Start-Transcript $logFileName -Force

. "C:\Framework-Scripts\secrets.ps1"

#
#  Launch the automation
Write-Output "Starting execution of test $testCycles on machine $sourceName" 

Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'
Select-AzureRmSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID" 

$tests_failed = $false
Set-Location C:\azure-linux-automation
foreach ($testCycle in $testCycles) {
    C:\azure-linux-automation\AzureAutomationManager.ps1 -xmlConfigFile $configFileName -runtests -email –Distro $distro -cycleName $testCycle -UseAzureResourceManager -EconomyMode
    if ($? -ne $true) {
        $tests_failed = $true
        break
    }
}

Stop-Transcript

if ($tests_failed -eq $true) {
    exit 1
} else {
    exit 0
}