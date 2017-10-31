$ErrorActionPreference = "Stop"
$DOCKER_GIT_REPO=$args[0]
$DOCKER_GIT_BRANCH=$args[1]
$CLONE_PATH=$args[2]
$GO_PATH=$args[3]
$DOCKER_TESTS_GIT_REPO=$args[4]
$DOCKER_TESTS_GIT_BRANCH=$args[5]

function Clone-Dockerd {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$repo,
        [Parameter(Mandatory=$true)]
        [string]$branch,
        [Parameter(Mandatory=$true)]
        [string]$path,
        [Parameter(Mandatory=$true)]
        [string]$tests_repo,
        [Parameter(Mandatory=$true)]
        [string]$tests_branch
    )

    if (Get-Service dockerd -ErrorAction SilentlyContinue) {
        Stop-Service dockerd
        sc.exe delete dockerd
    }

    if (Test-Path $path/docker) { Remove-Item -Force -Recurse $path/docker }
    git clone $repo -b $branch $path\docker

    if (Test-Path $path/docker_tests) { Remove-Item -Force -Recurse $path/docker_tests }
    git clone $tests_repo -b $tests_branch $path\docker_tests
}

function Build-Dockerd {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$path
    )

    # build both daemon and client
    # TODO because of broken patch we need to use and existing client,
    # otherwise use -Binary
    & $path\docker\hack\make.ps1
    #Remove-Item "$path\docker\bundles\docker.exe"
    cp "C:\docker.exe" "$path\docker\bundles"
}

$env:GOPATH="$GO_PATH"
$env:PATH +="C:\tool-chain\bin;"

if (-not (Test-Path $GO_PATH)) { Throw "GOPATH could not be found" }
if (-not (Test-Path $CLONE_PATH)) { Throw "BUILD PATH could not be found" }

Clone-Dockerd $DOCKER_GIT_REPO $DOCKER_GIT_BRANCH $CLONE_PATH $DOCKER_TESTS_GIT_REPO $DOCKER_TESTS_GIT_BRANCH
Build-Dockerd $CLONE_PATH