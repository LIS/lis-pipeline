$ErrorActionPreference = "Stop"
$GOPATH_BUILD_DIR=$args[0]
$DOCKER_TESTS_GIT_REPO=$args[1]
$DOCKER_TESTS_GIT_BRANCH=$args[2]
$NODE_IP=$args[3]
$ARTIFACTS_PATH=$args[4]
$DOCKER_CLIENT_PATH=$args[5]

$LINUX_CONTAINERS_PATH="C:\Program Files\Linux Containers"

function Register-DockerdService {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$build_path
    )

    $env:LCOW_SUPPORTED = "1"
    #$env:LCOW_API_PLATFORM_IF_OMITTED = "linux"
    $env:DOCKER_DEFAULT_PLATFORM="linux"
    Write-Host $env:LCOW_SUPPORTED
    Write-Host $env:LCOW_API_PLATFORM_IF_OMITTED

    if (Test-Path "c:\lcow" ) { 
        Remove-Item "c:\lcow" -Force -Recurse
        New-Item "c:\lcow" -ItemType Directory
    }

    cd $build_path\docker\bundles\
    New-Service -Name "dockerd" -BinaryPathName `
    "C:\service_wrapper.exe dockerd $build_path\docker\bundles\dockerd.exe -D --experimental --data-root C:\lcow"

    Write-Host "Docker service registration ran successfully"
}

function Start-DockerdService {
    Start-Service dockerd

    $service = Get-Service dockerd
    if ($service.Status -ne 'Running') {
        Write-Host "Dockerd service not running"
        Exit 1
    } else {
        Write-Host "Dockerd service started successfully"
    }
}

function Start-DockerTests {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$repo,
        [Parameter(Mandatory=$true)]
        [string]$branch,
        [Parameter(Mandatory=$true)]
        [string]$build_path,
        [Parameter(Mandatory=$true)]
        [string]$node_ip
    )

    cd $build_path
    $env:PATH +="$DOCKER_CLIENT_PATH"
    Write-Host $env:PATH

    cd docker_tests
    ./runTests.ps1 yes

    Write-Host "Docker tests ran successfully"
}

function Copy-Artifacts {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$artifact_path
    )


    if (Test-Path "$LINUX_CONTAINERS_PATH" ) { 
        Get-ChildItem -Path "$LINUX_CONTAINERS_PATH" -Include *.* -File -Recurse | foreach { $_.Delete()}
    }

    cd $artifact_path
    $initrd_root_dir = Get-ChildItem -Directory | Where-Object {$_.Name.contains("kernel")} | sort -Descending -Property CreationTime | select -first 1
    cp "$initrd_root_dir\initrd_artifact\initrd.img" "$LINUX_CONTAINERS_PATH"
    Write-Host "Initrd artifact copied from $initrd_root_dir\initrd_artifact\initrd.img to $LINUX_CONTAINERS_PATH successfully"

    cp "$initrd_root_dir\bootx64.efi" "$LINUX_CONTAINERS_PATH"
    Write-Host "bootx64.efi artifact copied from $initrd_root_dir\bootx64.efi to $LINUX_CONTAINERS_PATH successfully"

    Write-Host "Artifact copied successfully"
}

function Clean-Up {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$build_path
    )

    if (Get-Service dockerd -ErrorAction SilentlyContinue) {
        Stop-Service dockerd
        sc.exe delete dockerd
    }

    $docker_git_repo = "$build_path\docker\bundles\docker-tests"
    if (Test-Path $docker_git_repo ) { Remove-Item $docker_git_repo }

    Write-Host "Cleanup successful"

}

Clean-Up $GOPATH_BUILD_DIR
Copy-Artifacts $ARTIFACTS_PATH

#cd $GOPATH_BUILD_DIR\docker\bundles\
Register-DockerdService $GOPATH_BUILD_DIR
Start-DockerdService
Start-DockerTests $DOCKER_TESTS_GIT_REPO $DOCKER_TESTS_GIT_BRANCH $GOPATH_BUILD_DIR $NODE_IP