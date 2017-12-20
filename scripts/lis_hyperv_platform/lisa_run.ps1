param(
    [string] $WorkDir = ".",
    [string] $VMName = "kernel-validation",
    [string] $KeyPath = "C:\Path\To\Key",
    [string] $XmlTest = "TestName",
    [string] $ResultsPath = "C:\Path\To\Results"
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
        [string] $LisaTestXmlPath,
        [string] $ParentVHDPath
    )
    $xml = [xml](Get-Content $LisaTestXmlPath)
    $xml.config.VMs.vm[1].hardware.parentVhd = $ParentVHDPath
    $xml.Save($LisaTestXmlPath)
}

function Main {
    pushd "$WorkDir"
    $lisaTestXmlPath = "${env:Workspace}/scripts/lis_hyperv_platform/lisa_tests/minimal_lisa_test.xml"
    Edit-XmlTest $lisaTestXmlPath $env:LISAParentVHDPath
    pushd ".\lis-test\WS2012R2\lisa\"
    .\lisa.ps1 run $lisaTestXmlPath -dbg 3
    popd
    popd
}

Main
