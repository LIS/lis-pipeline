param (
    [String] $ClusterName,
    [String] $TestLocation,
    [String] $HostBuildPath,
    [String] $AgentPackagePath,
    [String] $OutputFile
)

$ErrorActionPreference = "Stop"
Import-module -Name TipNodeService -Force -Verbose

function Main {
    if (Test-Path $OutputFile) {
        Remove-Item -Path $OutputFile -Force
    }
    New-Item $OutputFile
    $OutputFile = Resolve-Path $OutputFile
    
    $hostEnv = @{}
    if ($HostBuildPath) {
        $hostEnv["ServerStandardCore_HVBaseName"] = $HostBuildPath
    }
    if ($AgentPackagePath) {
        $hostEnv["AgentPackage"] = $AgentPackagePath
    }
    
    $response = New-TipNodeSession -ClusterName $ClusterName -Region $TestLocation `
                    -NodeCount 1 -HostingEnvironment $HostEnv
    
    $sessonID = $response.SessionId
    $changeID = $response.ChangeId
    if ((-not $sessonID) -or (-not $changeID)) {
        throw "Invalid response from API, sessionID or changeID empty"
    }
    
    $deployState = "Creating"
    $timeout = 3000
    while (($deployState -ne "Finished") -and ($timeout -ge 0)) {
        $response = Get-TipNodeSessionChanges $sessionID $changeID
        $deployState = $response.Status
        if (-not $deployState) {
            throw "Invalid response from API"
        }
        
        Write-Host "Deploy State: $deployState"
        Start-Sleep 5
        $timeout -= 5
    }
    if ($deployState -ne "Finished") {
        throw "TiP node was not deployed in ${timeout} seccond. Aborting."
    }
    
    Set-Content -Value $sessionID -Path $OutputFile
}

Main