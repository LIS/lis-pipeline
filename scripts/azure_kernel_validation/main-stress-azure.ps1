param(
    [parameter(Mandatory=$true)]
    [String] $AzureSecretsPath,
    [parameter(Mandatory=$true)]
    [String] $TestCase,
    [parameter(Mandatory=$true)]
    [String] $AzureAuthXml,
    [String] $Identifier,
    [String] $WorkingDir = ".",
    [String] $AzureLocation = "westus2",
    [String] $KernelDir,
    [String] $TestParameters,
    [String] $BaseImage,
    [String] $TestIterations,
    [String] $StorageAccount,
    [String] $ResultsDest = ".",
    [String] $ResourceGroup,
    [Bool] $CleanVhd
)

$ErrorActionPreference = "Stop"

function Search-Kernel {
    param(
        [parameter(Mandatory=$true)]
        [String] $KernelDir,
        [parameter(Mandatory=$true)]
        [String] $PackageExtension
    )
    
    if (Test-Path $KernelDir) {
        $package = Get-ChildItem -Path $KernelDir | `
            Where-Object {$_.Name -NotMatch "dbg" -and $_.Name -Match "image" -and $_.Name -Match "$PackageExtension"}
        if ($package) {
            return $package
        }
    }
    return $false
}

function Copy-LatestResults {
    param(
        [parameter(Mandatory=$true)]
        [String] $ResultsPath,
        [parameter(Mandatory=$true)]
        [String] $ResultsDest
    )
    
    $latestLogs = Get-ChildItem $ResultsPath | Where { $_.PSIsContainer } | `
        Sort CreationTime -Descending | Select -First 1
    Move-Item -Path $latestLogs -Destination $ResultsDest
}

function Clean-AzureVhd {
    param(
        [parameter(Mandatory=$true)]
        [String] $ResourceGroup,
        [parameter(Mandatory=$true)]
        [String] $StorageAccount,
        [parameter(Mandatory=$true)]
        [string] $VHDName
    )

    $key = (Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroup -StorageAccountName $StorageAccount)[0]
    $context = New-AzureStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $key
    Remove-AzureStorageBlob -Container "vhds" -Blob $VHDName -Context $context
}

function Get-LisaCode {
    param(
        [parameter(Mandatory=$true)]
        [string] $LISAPath
    )
    
    if (Test-Path $LISAPath) {
        rm -Recurse -Force $LISAPath
    }
    git clone https://github.com/LIS/LISAv2.git $LISAPath
}

function Set-DeployStorageAccount {
    param(
        [parameter(Mandatory=$true)]
        [string] $RegionsXml,
        [parameter(Mandatory=$true)]
        [string] $Location,
        [parameter(Mandatory=$true)]
        [string] $StorageAccount
    )
    
    $RegionsXml = Resolve-Path $RegionsXml
    
    $xmlContent = [xml](Get-Content $RegionsXml)
    if ($xmlContent.AllRegions.$Location.StandardStorage) {
        $xmlContent.AllRegions.$Location.StandardStorage = $StorageAccount
    }
    $xmlContent.Save($RegionsXml)
}

function Search-TestXml {
    <#
    .SYNOPSIS
        Search all XML files in the given directory for the given test case
        If the test is found return the XML path.
    #>

    param(
        [parameter(Mandatory=$true)]
        [String] $XmlDir,
        [parameter(Mandatory=$true)]
        [String] $TestCase
    )
    
    $XmlDir = Resolve-Path $XmlDir
    
    $xmlNames = Get-ChildItem -Path $XmlDir
    foreach ($xmlName in $xmlNames) {
        $xmlContent = [xml](Get-Content $xmlName.FullName)
        
        foreach ($lisaTest in $xmlContent.TestCases.Test) {
            if ($lisaTest.TestName -eq $TestCase) {
                return $xmlName.FullName
            }
        }
    }
    return $false
}

function Set-TestParameters {
    param(
        [parameter(Mandatory=$true)]
        [String] $XmlPath,
        [parameter(Mandatory=$true)]
        [String] $TestCase,
        [parameter(Mandatory=$true)]
        [String] $TestParameters
    )
    
    $XmlPath = Resolve-Path $XmlPath
    
    $xmlContent = [xml](Get-Content $XmlPath)
    foreach ($lisaTest in $xmlContent.TestCases.Test) {
        if ($lisaTest.TestName -eq $TestCase) {
            if (-not $lisaTest.TestParameters) {
                $testParamsChild = $xml.CreateElement("TestParameters")
                $paramChild = $xml.CreateElement("param")
                $testParamsChild.AppendChild($paramChild)
                $lisaTest.AppendChild($testParamsChild)
            }
            $testParams = $TestParameters
            $testParams = $testParams.Split(";")
            foreach ($param in $testParams) {
                $newParam = $true
                $argument = $param.Split("=")[0]
                foreach ($xmlParam in $lisaTest.TestParameters.ChildNodes) {
                    if ($xmlParam.'#text'.Split("=")[0] -eq $argument){
                        $xmlParam.'#text' = $param
                        $newParam = $false
                        break
                    }
                }
                if ($newParam) {
                    $paramChild = $xml.CreateElement("param")
                    $paramChild.set_InnerText($param)
                    $lisaTest.TestParameters.AppendChild($paramChild)
                }
            }
        }
    }
    $xmlContent.Save($XmlPath)
}

function Prepare-Env {
    param(
        [parameter(Mandatory=$true)]
        [String] $LISAPath,
        [parameter(Mandatory=$true)]
        [String] $AzureXmlPath,
        [String] $KernelDir,
        [String] $Location,
        [String] $StorageAccount,
        [String] $AzureAuthXml
    )
    
    $AzureXmlPath = Resolve-Path $AzureXmlPath
    $KernelDir = Resolve-Path $KernelDir
    $regionsXml = Join-Path $LisaPath "XML\RegionAndStorageAccounts.xml"
    
    Push-Location $LisaPath
    & .\Utilities\UpdateGlobalConfigurationFromXmlSecrets.ps1 `
        -XmlSecretsFilePath $AzureXmlPath
    Set-DeployStorageAccount -RegionsXml $regionsXml `
        -Location $Location -StorageAccount $StorageAccount
    & .\Utilities\AddAzureRmAccountFromSecretsFile.ps1 -customSecretsFilePath $AzureAuthXml
    
    # Note (mbivolan): The kernel package must be in a path relative to the LISA folder
    # For simplicity it will be copied in the LISA folder
    if ($KernelDir) {
        Remove-Item -Force *.deb
        $package = Search-Kernel -KernelDir $KernelDir -PackageExtension "deb"
        if ($package) {
            Copy-Item -Path $package.FullName -Destination "."
        } else {
            Write-Host "Kernel folder or kernel file do not exist"
        }
    }
    Pop-Location
}

function Run-LisaTest {
    param(
        [parameter(Mandatory=$true)]
        [String] $LISAPath,
        [parameter(Mandatory=$true)]
        [String] $Location ,
        [parameter(Mandatory=$true)]
        [String] $TestCase,
        [String] $TestParameters,
        [String] $TestIterations = "1",
        [bool] $CustomKernel,
        [String] $ARMImage,
        [String] $OSvhd,
        [String] $Identifier = "",
        [String] $ResultsDest
    )
    
    $xmlDir = Join-Path $LISAPath "XML\TestCases"
    $resultsDir = Join-Path $LISAPath "TestResults"
    
    Push-Location $LISAPath
    if ($TestParameters) {
        $xmlPath = Search-TestXml -XmlDir $xmlDir -TestCase $TestCase
        Set-TestParameters -XmlPath $xmlPath -TestCase $TestCase `
            -TestParameters $TestParameters
    }
    
    $lisaParameters = @{"TestPlatform" = "Azure"; "TestLocation" = $Location; `
        "RGIdentifier" = $Identifier; `
        "TestNames" = $TestCase; "TestIterations" = $TestIterations}
    if ($CustomKernel){
        $package = Search-Kernel -KernelDir "." -PackageExtension "deb"
        $lisaParameters += @{"CustomKernel" = "localfile:" + $package.Name}
    }
    if ($ARMImage){
        $lisaParameters += @{"ARMImageName" = "'$ARMImage'"}
    } elseif ($OSvhd) {
        $lisaParameters += @{"OsVHD" = $OSvhd}
    }
    
    echo $lisaParameters

    powershell.exe -Command ".\Run-LisaV2.ps1" -args @lisaParameters
    
    if ($ResultsDest){
        Copy-LatestResults -ResultsPath $resultsDir -ResultsDest $ResultsDest
    } else {
        Remove-Item -Recurse -Force "$resultsDir\*"
    }
    
    Pop-Location
} 

function Main {
    $WorkingDir = Join-Path $WorkingDir $Identifier
    if ( -not (Test-Path $WorkingDir)) {
        New-Item -Type Directory -Path $WorkingDir
    }
    $WorkingDir = Resolve-Path $WorkingDir
    $LisaDir = Join-Path $WorkingDir "LISAv2"
    if ( -not (Test-Path $ResultsDest)) {
        New-Item -Type Directory -Path $ResultsDest
    }
    $ResultsDest = Resolve-Path $ResultsDest
    
    Get-LisaCode -LisaPath $LisaDir
    Prepare-Env -LisaPath $LisaDir -AzureXmlPath $AzureSecretsPath `
        -KernelDir $KernelDir -Location $AzureLocation `
        -StorageAccount $StorageAccount -AzureAuthXml $AzureAuthXml
    
    Run-LisaTest -LisaPath $LisaDir -TestCase "CAPTURE-VHD-BEFORE-TEST" `
        -CustomKernel $true -ARMImage $BaseImage -Location $AzureLocation `
        -Identifier $Identifier
    
    $envFile = Join-Path $LisaDir "CapturedVHD.azure.env"
    $generatedVHD = Get-Content $envFile
    
    Run-LisaTest -LisaPath $LisaDir -TestCase $TestCase `
        -TestParameters $TestParameters -TestIterations $TestIterations `
        -OSvhd $generatedVHD -Location $AzureLocation -Identifier $Identifier `
        -ResultsDest $ResultsDest
    
    if ($CleanVhd) {
        Clean-AzureVhd -ResourceGroup $ResourceGroup -StorageAccount $StorageAccount `
            -VHDName $generatedVHD
    }
    
    Remove-Item -Recurse $WorkingDir
}

Main
