param(
    [string] $WorkDir = ".",
    [string] $VMName = "kernel-validation",
    [string] $KeyPath = "C:\Path\To\Key",
    [string] $XmlTest = "TestName",
    [String] $AzureToken ,
    [String] $AzureUrl ,
    [String] $KernelFolder ,
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
    ($KeyName, $XmlName) = Get-Dependencies $KeyPath $XmlTest
    Edit-XmlTest $VMName $XmlName $KeyName 
    pushd ".\lis-test\WS2012R2\lisa\"
    lisaParams = 'SHARE_URL="' + $AzureUrl + '"' + ';AZURE_TOKEN="' + $AzureToken + '"' + ";KERNEL_FOLDER=$KernelFolder"
    .\lisa.ps1 run xml\$XmlName -dbg 3 -testParams $lisaParams
    popd
    popd
}

Main
