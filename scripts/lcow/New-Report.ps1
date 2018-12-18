param (
    [String] $StageName,
    [String] $TestType,
    [String] $LogPath,
    [int] $ExitCode,
    [String] $ReportDestination,
    [String] $BuildNumber,
    [String] $StageSummary
)

$BOOT_SUMMARY = "boot_speed.log"
$LINUXKIT_SUMMARY = "SUMMARY.json"
$HYPERV_DOCKER_SUMMARY = "AppSummary.csv"
$WSL_SUMMARY = "summary.log"

function Parse-LinuxKitResults {
    param (
        [String] $LogPath,
        [String] $StageName,
        [String] $BuildNumber
    )
    
    $results = @()
    
    $summaryPath = Join-Path $LogPath $LINUXKIT_SUMMARY
    if (Test-Path $summaryPath) {
        $summaryContent = Get-Content $summaryPath | ConvertFrom-Json
    } else {
        throw "Cannot find summary file: ${LINUXKIT_SUMMARY}"
    }
    
    $testResults = $summaryContent.results
    foreach ($result in $testResults) {
        $test = @{}
        $test["BuildNumber"] = $BuildNumber
        $test["TestStage"] = $StageName
        $test["TestName"] = $result.name
        $test["TestDate"] = Get-Date -UFormat "%Y-%m-%d"
        if ($result.result -ne 0) {
            $test["TestResult"] = "FAIL"
        } else {
            $test["TestResult"] = "PASS"
        }
        
        $results += $test
    }
    
    return $results
}

function Parse-HyperVDockerResults {
    param (
        [String] $LogPath,
        [String] $StageName,
        [String] $BuildNumber
    )
    
    $results = @()
    $summaryPath = Join-Path $LogPath $HYPERV_DOCKER_SUMMARY
    if (Test-Path $summaryPath) {
        $summaryContent = Get-Content $summaryPath -Raw
    } else {
        throw "Cannot find summary file: ${$HYPERV_DOCKER_SUMMARY}"
    }

    $testResults = $($summaryContent -split "`r`n`r`n")
    foreach ($result in $testResults) {
        if ($result -eq "" ) {
            continue
        }
        $result =  $result.Split("`n")
        $test = @{}
        $test["BuildNumber"] = $BuildNumber
        $test["TestStage"] = $StageName
        $test["TestDate"] = Get-Date -UFormat "%Y-%m-%d"
        $test["TestName"] = $result[0].Trim()
        if ($result[12].Split(":")[1].Trim() -ne "0") {
            $test["TestResult"] = "FAIL"
        } else {
            $test["TestResult"] = "PASS"
        }

        $results += $test
    }

    return $results
}

function Parse-LTPResults {
    param (
        [String] $LogPath,
        [String] $StageName,
        [String] $BuildNumber
    )
    
    $results = @()
    $summaryPath = $(Get-ChildItem ${LogPath}\ltp-results.log)
    if (Test-Path $summaryPath) {
        $summaryContent = Get-Content $summaryPath
    } else {
        throw "Cannot find summary file: ${$HYPERV_DOCKER_SUMMARY}"
    }
    
    $testResults = $($summaryContent | Where-Object {$_ -cmatch "PASS" -or $_ -cmatch "FAIL"})
    foreach ($result in $testResults) {
        if ($result -eq "" ) {
            continue
        }
        $result = $($result -replace '\s+', ' ')
        $test = @{}
        $test["BuildNumber"] = $BuildNumber
        $test["TestStage"] = $StageName
        $test["TestDate"] = Get-Date -UFormat "%Y-%m-%d"
        $test["TestName"] = $result.Split(" ")[0]
        $test["TestResult"] = $result.Split(" ")[1]
        
        $results += $test
    }
    
    return $results
}

function Parse-WSLResults {
    param (
        [String] $LogPath,
        [String] $StageName,
        [String] $BuildNumber
    )
    
    $results = @()
    $summaryPath = Join-Path $LogPath $WSL_SUMMARY
    if (Test-Path $summaryPath) {
        $summaryContent = Get-Content $summaryPath
    } else {
        throw "Cannot find summary file: ${$WSL_SUMMARY}"
    }
    
    foreach ($result in $summaryContent) {
        if ($result -eq "") {
            continue
        }
        
        $test = @{}
        $test["BuildNumber"] = $BuildNumber
        $test["TestStage"] = $StageName
        $test["TestDate"] = Get-Date -UFormat "%Y-%m-%d"
        $test["TestName"] = $result.Split(" ")[0]
        if ($result.Split(" ")[2].Split(":")[1].Trim() -eq "0") {
            $test["TestResult"] = "PASS"
        } else {
            $test["TestResult"] = "FAIL"
        }
        
        $results += $test
    }
    
    return $results
}

function New-JsonReport {
    param (
        [String] $ReportDestination,
        [Array] $Results,
        [String] $ReportName
    )
    
    $reportPath = Join-Path $ReportDestination $ReportName
    
    $jsonReport = $(ConvertTo-Json @($Results))
    echo $jsonReport
    Set-Content -Path $reportPath -Value $jsonReport
    
}

function Main {
    if (Test-Path $ReportDestination) {
        Remove-Item -Recurse -Force $ReportDestination
    }
    if (Test-Path $StageSummary) {
        Remove-Item $StageSummary
    }
    New-Item -Type Directory -Path $ReportDestination
    $ReportDestination = Resolve-Path $ReportDestination
    if ($LogPath) {
        $LogPath = Resolve-Path $LogPath
    }

    $results = $null
    $summary = $null
    Switch ($TestType) {
        "STRESS" {
            $results = @{"TestStage" = $StageName; "TestName" = $StageName; `
                         "TestDate" = $(Get-Date -UFormat "%Y-%m-%d"); `
                         "BuildNumber" = $BuildNumber}
            if ($ExitCode -ne 0) {
                $results["TestResult"] = "FAIL"
            } else {
                $results["TestResult"] = "PASS"
            }
            break
        }
        "BOOT_TEST" {
            $results = @{"TestStage" = $StageName; "TestName" = $StageName; `
                         "TestDate" = $(Get-Date -UFormat "%Y-%m-%d"); `
                         "BuildNumber" = $BuildNumber}
            if ($ExitCode -ne 0) {
                $results["TestResult"] = "FAIL"
            } else {
                $results["TestResult"] = "PASS"
            }
            $summaryPath = $(Get-ChildItem ${LogPath}\${BOOT_SUMMARY})
            if (Test-Path $summaryPath) {
                $summaryContent = Get-Content $summaryPath
            } else {
                throw "Cannot find summary file: ${BOOT_SUMMARY}"
            }
            $summary = "Boot Time: $summaryContent"
            break
        }
        "LINUXKIT" {
            $results = Parse-LinuxKitResults -LogPath $LogPath -StageName $StageName `
                -BuildNumber $BuildNumber
            break
        }
        "DOCKER_HYPERV" {
            $results = Parse-HyperVDockerResults -LogPath $LogPath -StageName $StageName `
                -BuildNumber $BuildNumber
            break
        }
        "LTP" {
            $results = Parse-LTPResults -LogPath $LogPath -StageName $StageName `
                -BuildNumber $BuildNumber
            break
        }
        "WSL" {
            $results = Parse-WSLResults -LogPath $LogPath -StageName $StageName `
                -BuildNumber $BuildNumber
            break
        }
        default {
            throw "Test type not supported"
        }
    }
    
    if ($summary -and $StageSummary) {
        Set-Content -Path $StageSummary -Value $summary
    }
    
    New-JsonReport -ReportDestination $ReportDestination -Results $results `
        -ReportName "${StageName}_report.json"
}

Main