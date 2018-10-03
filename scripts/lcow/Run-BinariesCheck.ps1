param (
    [String] $XmlConfig,
    [String] $WorkDir,
    [String] $BinariesPath,
    [String] $LogDestination
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$commonModulePath = Join-Path $scriptPath "CommonFunctions.psm1"
Import-Module $commonModulePath

$TEST_IMAGE_NAME = "bin-check-img"
$CPIO_PATH = "C:\Program Files\Linux Containers\initrd.img"
$GZ_PATH = "C:\Program Files\git\usr\bin\gzip.exe"
$IMAGE_NAME = "core-binaries-check"

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

function Convert-CpioToTar {
    param (
        [String] $CpioPath
    )

    if (-not (Test-Path $CpioPath)) {
        throw "Cannot find cpio image"
    }
    
    New-Item -Type "Directory" -Path "./convert-temp" | Out-Null
    $convertDir = Resolve-Path "./convert-temp"
    $tempCpioPath = Join-Path $convertDir "${IMAGE_NAME}.cpio"
    Copy-Item -Path $CpioPath -Destination $tempCpioPath | Out-Null

    $convertCommand = "cd /tmp && mkdir temp-dir && cd temp-dir && cat ../${IMAGE_NAME}.cpio | cpio -idv && tar -cvf ../${IMAGE_NAME}.tar *"
    # base debian image fails to install the cpio image if used in the command on top
    # mbivolan/debian-cpio is a debian based image with the cpio package preinstalled
    docker run -v "${convertDir}:/tmp" --platform linux mbivolan/debian-cpio sh -xec $convertCommand | Out-Null
    
    $tempTarPath = Join-Path $convertDir "${IMAGE_NAME}.tar"
    
    return $tempTarPath
}


function Import-Image {
    param (
        [String] $ImagePath
    )
    
    if (-not (Test-Path $ImagePath)) {
        throw "Cannot find test image: $ImagePath"
    }
    
    $imageID = $(docker import --platform linux $ImagePath)
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
    
    $tarPath = Convert-CpioToTar -CpioPath $CPIO_PATH
    
    $containerID = Import-Image -ImagePath $tarPath

    Execute-Test -ContainerID $containerID -XmlConfig $XmlConfig `
        -LogDestination $LogDestination

    Pop-Location
}

Main
