param(
    [parameter(Mandatory=$true)]
    [String] $DockerGitRepo,
    [parameter(Mandatory=$true)]
    [String] $DockerGitBranch,
    [parameter(Mandatory=$true)]
    [String] $ClonePath,
    [parameter(Mandatory=$true)]
    [String] $GoPath,
    [parameter(Mandatory=$true)]
    [String] $DockerTestsGitRepo,
    [parameter(Mandatory=$true)]
    [String] $DockerTestsGitBranch
)

$ErrorActionPreference = "Stop"

function Clone-Dockerd {
    param(
        [String] $Repo,
        [String] $Branch,
        [String] $Path,
        [String] $TestsRepo,
        [String] $TestsBranch
    )

    if (Get-Service "dockerd" -ErrorAction SilentlyContinue) {
        Stop-Service "dockerd" -Force
        sc.exe delete "dockerd"
        if ($LastExitCode) {
            Write-Host "Failed to remove Docker daemon"
        }
    }

    if (Test-Path "$Path\docker") {
        Remove-Item -Force -Recurse "$Path\docker"
    }
    git.exe clone $Repo -b $Branch "$Path\docker"
    if ($LastExitCode) {
        Write-Host "Could not clone docker"
        exit 1
    }
    Write-Host "Docker cloned successfully"
    
    if (Test-Path "$Path\docker_tests") {
        Remove-Item -Force -Recurse "$Path\docker_tests"
    }
    git.exe clone $TestsRepo -b $TestsBranch "$Path\docker_tests"
    if ($LastExitCode) {
        Write-Host "Could not clone docker-tests"
        exit 1
    }
    Write-Host "docker-tests cloned successfully"
}

function Build-Dockerd {
    param(
        [String] $Path
    )

    # build both daemon and client
    # TODO because of broken patch we need to use and existing client,
    # otherwise use -Binary
    & $Path\docker\hack\make.ps1
    Copy-Item "C:\docker.exe" "$Path\docker\bundles"
}

function Main {
    $ClonePath = "${env:HOMEDRIVE}\${env:HOMEPATH}\$ClonePath"
    $GoPath = "${env:HOMEDRIVE}\${env:HOMEPATH}\$GoPath"

    Write-Host "Clone Path : $ClonePath"
    Write-Host "Go Path : $GoPath"

    $env:GOPATH = $GoPath
    $env:PATH +=";C:\tool-chains\bin"

    if (-not (Test-Path $GoPath)) { Throw "$GoPath could not be found" }
    if (-not (Test-Path $ClonePath)) { Throw "$ClonePath PATH could not be found" }

    Clone-Dockerd $DockerGitRepo $DockerGitBranch $ClonePath `
        $DockerTestsGitRepo $DockerTestsGitBranch
    Build-Dockerd $ClonePath
}

Main
