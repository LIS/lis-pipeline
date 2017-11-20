param (
    [parameter(Mandatory=$true)]
    [String] $JobPath,
    [parameter(Mandatory=$true)]
    [String] $VHDPath,
    [parameter(Mandatory=$true)]
    [String] $KernelPath,
    [parameter(Mandatory=$true)]
    [String] $InstanceName,
    [parameter(Mandatory=$true)]
    [String] $IdRSAPub,
    [parameter(Mandatory=$true)]
    [String] $VHDType
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

$scriptPath1 = (Get-Item $scriptPath).parent.FullName
. "$scriptPath1\backend.ps1"
. "$scriptPath1\common_functions.ps1"

function Main {
    Assert-PathExists $JobPath
    Assert-PathExists $VHDPath
    Assert-PathExists $KernelPath

    Resize-VHD -Path $VHDPath -SizeBytes 30GB

    $backend = [HypervBackend]::new(@("localhost"))
    $instance = [HypervInstance]::new($backend, $InstanceName, $VHDPath)

    Write-Host "Starting Setup-Metadata script."
    & "$scriptPath/setup_metadata.ps1" -JobPath $JobPath `
                                       -KernelPath $KernelPath `
                                       -IdRSAPub $IdRSAPub -VHDType $VHDType
    if ($LastExitCode -ne 0) {
        throw $Error[0]
    }

    $instance.CreateInstance()
    $instance.AttachVMDvdDrive("$JobPath/configdrive.iso")
    $instance.StartInstance()
}

Main
