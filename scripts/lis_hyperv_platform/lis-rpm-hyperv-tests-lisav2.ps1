[CmdletBinding()]
param(
    [parameter(Mandatory = $true)]
    [String] $JobId,
    [parameter(Mandatory = $true)]
    [String] $DistroVersion,
    [parameter(Mandatory = $true)]
    [String] $TestCategory,
    [String] $TestArea,
    [String] $TestNames,
    [string] $TestTag,
    [string] $TestPriority,
    [String] $LISAImagesShareUrl,
    [String] $LisUrl,
    [String] $LisOldUrl,
    [String] $ExcludeTests,
    [String] $IncludeTests,
    [string] $ExecutionTag,
    [String] $Delay
)

foreach ($key in $MyInvocation.BoundParameters.keys) {
    $value = (get-variable $key).Value
    write-host "$key -> $value"
}

function Main {
    if (!$TestCategory) { $TestCategory = "All" }
    if (!$TestArea)     { $TestArea = "All" }
    if (!$TestNames)    { $TestNames = "All" }
    if (!$TestTag)      { $TestTag = "All" }
    if (!$TestPriority) { $TestPriority = "All" }

    Write-Output "Sleeping $Delay seconds..."
    Start-Sleep $Delay

    Write-Host "Getting the proper VHD folder name for LISA with $DistroVersion"
    $imageFolder = Join-Path $LISAImagesShareUrl $DistroVersion.split("_")[0]
    $imageFolder = Join-Path $imageFolder $DistroVersion
    $parentVhd = $(Get-ChildItem $imageFolder | Where-Object { $_.Extension -eq ".vhd" -or $_.Extension -eq ".vhdx"} | Sort LastWriteTime | Select -Last 1).Name
    $VHD_Path = Join-Path $imageFolder $parentVhd
    $VMgeneration = "1"
    if ($DistroVersion -like "*gen2vm*") {
        $VMgeneration = "2"
    }
    Write-Output "Starting LISAv2"
    try {
        $SourceVHDPath = $VHD_Path | Split-Path -Parent
        $OsVHD = $VHD_Path | Split-Path -Leaf
        if ((Test-Path $VHD_Path) -or ($VHD_Path.StartsWith("http"))) {
            Write-Host "ComputerName: $env:computername"
            Write-Host "VHD : $VHD_Path"
            $command = ".\Run-LisaV2.ps1 -TestPlatform HyperV"
            $command += " -XMLSecretFile '$env:Azure_Secrets_File'"
            $command += " -TestLocation 'localhost'"
            $command += " -RGIdentifier '$JobId'"
            $command += " -OsVHD '$VHD_Path'"
            $command += " -TestCategory '$TestCategory'"
            $command += " -TestArea '$TestArea'"
            $command += " -VMGeneration '$VMgeneration'"
            $command += " -EnableTelemetry"
            $command += " -ExitWithZero"
            if ($ExecutionTag) {
                $command += " -ResultDBTestTag '$ExecutionTag'"
            }
            if ($IncludeTests) {
                $command += " -TestNames '$IncludeTests'"
            }
            if ($ExcludeTests) {
                $command += " -ExcludeTests '$ExcludeTests'"
            }
            if ($TestArea -imatch "LIS_DEPLOY") {
                $command += " -CustomTestParameters 'LIS_OLD_URL=$LisOldUrl;LIS_CURRENT_URL=$LisUrl'"
                $command += " -OverrideVMSize 'Standard_A1'"
            } else {
                $command += " -CustomLIS '$LisUrl'"
                $command += " -ResourceCleanup Delete"
            }
            Write-Output $PsCmd
            powershell.exe -NonInteractive -ExecutionPolicy Bypass `
                -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$command;EXIT $global:LastExitCode"
        }
        else {
            Write-Output "Unable to locate VHD : $VHD_Path."
        }
    }
    catch {
        $ErrorMessage =  $_.Exception.Message
		Write-Output "EXCEPTION : $ErrorMessage"
    }
}

Main
