function Prepare-Env {
    param (
        [String] $BinariesPath,
        [String] $TestPath
    )
    
    if (Test-Path $BinariesPath) {
        $env:PATH = $BinariesPath + ";" + $env:PATH
    } else {
        Write-Output "Error: Cannot find required binaries"
    }
    
    $randomIdentifier = Get-Random -Maximum 1000
    $dockerdDir = "C:\Docker-Workspace"
    if (-not (Test-Path $dockerdDir)){
        New-Item -Type Directory -Path $dockerdDir
    }
    $dockerdDir = Join-Path $dockerdDir "DockerDir_${randomIdentifier}"
    if (Test-Path $dockerdDir) {
        Remove-Item -Recurse -Force $dockerdDir
    }
    New-Item -Type Directory -Path $dockerdDir
    
    $dockerdData = Start-Process dockerd.exe -ArgumentList '-D', '--experimental', '--data-root', `
        "${dockerdDir}", "-H", "npipe://\\.\\pipe\\docker_engine${randomIdentifier}" `
        -NoNewWindow -RedirectStandardOutput '${dockerdDir}\dockerd.out' `
        -RedirectStandardError '${dockerdDir}\dockerd.err' -Passthru
    Start-Sleep 20
    
    [Environment]::SetEnvironmentVariable("DOCKER_HOST", "npipe:////./pipe/docker_engine${randomIdentifier}", "Process")
    $dockerID = $dockerdData.Id
    return $dockerID
}
