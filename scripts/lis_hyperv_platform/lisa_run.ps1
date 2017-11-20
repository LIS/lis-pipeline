param(
    [string] $WorkDir = ".",
    [string] $VMName = "kernel-validation",
    [string] $KeyPath = "C:\Path\To\Key",
    [string] $XmlTest = "TestName",
    [string] $ResultsPath = "C:\Path\To\Results",
    [bool] $GetDeps = 1
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Get-Dependencies {
    param(
        [string] $keyPath ,
        [string] $xmlTest
    )
    if ( Test-Path $keyPath ){
        cp "$keyPath" ".\lis-test\WS2012R2\lisa\ssh"
    }
    $keyName = ([System.IO.Path]::GetFileName($keyPath))
    if ( Test-Path $xmlTest ){
        cp $xmlTest ".\lis-test\WS2012R2\lisa\xml"
        $xmlName = ([System.IO.Path]::GetFileName($xmlTest))
    } else {
        $xmlName = $xmlTest
    }
    return ($keyName, $xmlName) 
}

function Edit-XmlTest {
    param(
        [string] $vmName ,
        [string] $xmlName ,
        [string] $keyName
    )
    pushd ".\lis-test\WS2012R2\lisa\xml"
    $xml = [xml](Get-Content $xmlName)
    $xml.config.VMs.vm.vmName = $vmName
    $xml.config.VMs.vm.sshKey = $keyName
    $xml.Save("$pwd\$xmlName")
    popd
}

function Main {
    pushd "$WorkDir"
    if ($GetDeps) {
        if ( Test-Path .\lis-test){
            rm -Recurse -Force .\lis-test
        }
        git clone https://github.com/mbivolan/lis-test.git
        Invoke-WebRequest -Uri "https://the.earth.li/~sgtatham/putty/0.70/w32/putty.zip" -OutFile "PuttyBinaries.zip"
        if ($LastExitCode){
            throw "Failed to download Putty binaries"
        }
        Expand-Archive .\PuttyBinaries.zip -DestinationPath ".\lis-test\WS2012R2\lisa\bin"
    }
    
    ($KeyName, $XmlName) = Get-Dependencies $KeyPath $XmlTest
    Edit-XmlTest $VMName $XmlName $KeyName 
    pushd ".\lis-test\WS2012R2\lisa\"
    .\lisa.ps1 run xml\$XmlName -dbg 3
    popd
    popd
}

Main
