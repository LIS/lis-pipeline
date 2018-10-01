param (
    [String] $XmlConfig,
    [String] $ImageDir,
    [String] $WorkDir,
    [String] $BinariesPath,
    [String] $LogDestination
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$commonModulePath = Join-Path $scriptPath "CommonFunctions.psm1"
Import-Module $commonModulePath

$TEST_IMAGE_NAME = "bin-check-img"
$BZ_PATH = "C:\Program Files\git\usr\bin\bzip2.exe"
$IMAGE_NAME = "core-image-minimal-lcow.tar.bz2"

function Get-TestCommand {
    param (
        [Switch] $FullPath,
        [String] $DefParam,
        $BinData
    )
    
    if ($FullPath -and $BinData.Path) {
        $command = $BinData.Path
    } elseif ((-not $FullPath) -and $BinData.'#text') {
        $command = $BinData.'#text'
    } else {
        Write-Host "Error: Binary file not specified"
        return $false
    }

    if ($BinData.VersionParam) {
        $param = $BinData.VersionParam
    } elseif ($DefParam) {
        $param = $DefParam
    } else {
        Write-Host "Warning: Version parameter not specified"
    }
    
    if ($BinData.ParseCommand) {
        $parseComm = $BinData.ParseCommand
    }
    
    $comm = "${command} ${param} ${parseComm}"
    return $comm
}

function Import-Image {
    param (
        [String] $ImageDir
    )
    
    $tarFile = Join-Path $ImageDir $IMAGE_NAME
    if (-not (Test-Path $tarFile)) {
        throw "Cannot find an image named: $TEST_IMAGE_NAME"
    }
    
    Copy-Item -Path $tarFile -Destination "."
    & $BZ_PATH -dk $IMAGE_NAME
    $imageName = $IMAGE_NAME.Substring(0, $IMAGE_NAME.LastIndexOf('.'))
    
    $imageID = $(docker import --platform linux $imageName)
    if ($(docker ps -a -q)) {
        docker rm $(docker ps -a -q) --force | Out-Null
    }
    docker run --platform linux --rm -td $imageID sh | Out-Null
    $containerID = $(docker ps)[1].Split(" ")[0]
    
    return $containerID
}

function Execute-Test {
    param (
        [String] $ContainerID,
        [String] $XmlConfig,
        [String] $LogDestination
    )

    $xmlConf = [xml](Get-Content $XmlConfig)
    $defaultParam = $xmlConf.binaries.defaultVersionParameter
    $logPath = Join-Path $LogDestination "check.log"
    
    foreach ($bin in $xmlConf.binaries.bin) {
        $logMsg = "`n$($bin.'#text'):"
        $version = $bin.Version
        
        $command = Get-TestCommand -BinData $bin -DefParam $defaultParam
        echo $command
        if ($command) {
            $msg = $(docker exec $containerID sh -xec "${command}")
            if ($LASTEXITCODE -ne 127) {
                $msg = $($msg | Out-String)
                if ($msg.Contains($version)) {
                    $logMsg += " Version matches"
                } else {
                    $logMsg += " Version does not match `nOutput: ${msg}"
                }
                echo "${logMsg}" >> $logPath
                continue
            }
        }    
                
        $command = Get-TestCommand -BinData $bin -DefParam $defaultParam -FullPath
        if ($command) {
            $msg = $(docker exec $containerID sh -xec "${command}")
            if (-not $LASTEXITCODE -ne 127) {
                $msg = $($msg | Out-String)
                if ($msg.Contains($version)) {
                    $logMsg += "Version matches"
                } else {
                    $logMsg += "Version does not match `nOutput: ${msg}"
                }
                echo "${logMsg}" >> $logPath
                continue
            }
        }
        
        $logMsg += "Command not found in path or parameter is wrong"
        echo "${logMsg}" >> $logPath
    }

    return 0
}

function Main {
    if (-not $WorkDir) {
        $WorkDir = "binaries-check"
    }
    if (Test-Path $WorkDir) {
        Remove-Item -Recurse $WorkDir
    }
    if (Test-Path $LogDestination) {
        Remove-Item -Recurse $LogDestination
    }

    New-Item -Type Directory -Path $WorkDir
    $WorkDir = Resolve-Path $WorkDir
    New-Item -Type Directory -Path $LogDestination
    $LogDestination = Resolve-Path $LogDestination
    $ImageDir = Resolve-Path $ImageDir
    $XmlConfig = Resolve-Path $XmlConfig

    Push-Location $WorkDir
    
    Prepare-Env -BinariesPath $BinariesPath
    
    $containerID = Import-Image -ImageDir $ImageDir

    Execute-Test -ContainerID $containerID -XmlConfig $XmlConfig `
        -LogDestination $LogDestination

    Pop-Location
}

Main
