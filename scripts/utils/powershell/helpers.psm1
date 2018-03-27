$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2
Import-Module Dism

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

function login_azure {
    param (
        [string] $rg = "", 
        [string] $sa = "", 
        [string] $location = "" ,
        [bool] $createOnError = $false)

    . "C:\Framework-Scripts\secrets.ps1"

    Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx' > $null
    Select-AzureRmSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID" > $null

    if ($rg -ne "" -and $sa -ne "") {
        $existingAccount = Get-AzureRmStorageAccount -ResourceGroupName $rg -Name $sa
        if ($? -eq $true) {
            #
            #  Existing account -- use it
            $currentLoc = ($existingAccount.Location).ToString()

            if ($currentLoc -ne $location) {
                if ($false -eq $createOnError) {
                #
                    #  Wrong region and we're suppposed to use existing.  This won't work, but we may not care         
                    Write-Warning "***************************************************************************************"
                    Write-Warning "Storage account $sa is in different region ($currentLoc) than current ($location)."
                    Write-Warning "       You will not be able to create any virtual machines from this account!"
                    Write-Warning "***************************************************************************************"
                    Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $sa
                } else {
                    #
                    #  Take it out and start over
                    Remove-AzureRmStorageAccount -ResourceGroupName $rg -Name $sa -Force
                    New-AzureRmStorageAccount -ResourceGroupName $rg -Name $sa -Kind Storage -Location $location -SkuName Standard_LRS
                    Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $sa
                }
            } else {
                #
                #  Account is present and location is good.  Use this one.
                Write-Verbose "Using existing storage account $sa in resource group $rg"
            }
        } elseif ($false -eq $createOnError) {
            Write-Warning "***************************************************************************************"
            Write-Warning "Storage account $sa does not exist in location $location. and CreateOnError was not set."
            Write-Warning "***************************************************************************************"
            $sa = $null
        } else {
            New-AzureRmStorageAccount -ResourceGroupName $rg -Name $sa -Kind Storage -Location $location -SkuName Standard_LRS 
            Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $sa
        }
    }

    return $sa
}

function make_cred () {
    . "C:\Framework-Scripts\secrets.ps1"

    $pw = convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PASS" 
    $cred = new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$pw

    return $cred
}

function make_cred_initial () {
    . "C:\Framework-Scripts\secrets.ps1"

    $pw = convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PAS2" 
    $cred = new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$pw

    return $cred
}

function Assert-PathExists {
    param(
        [String] $Path
    )
    if (!(Test-Path $Path)) {
       throw "Path $Path not found."
    }

}

function Assert-URLExists {
    param(
        [String] $URL
    )

    Write-Host "Checking Kernel URL"
    $httpRequest = [System.Net.WebRequest]::Create($URL)
    $httpResponse = $httpRequest.GetResponse()
    $httpStatus = [int]$httpResponse.StatusCode

    if ($httpStatus -ne 200) {
        Write-Host "URL $URL cannot be reached."
        throw "URL $URL cannot be reached."
    }

    $httpResponse.Close()
}

function Execute-WithRetry {
    param(
        [Parameter(Mandatory=$true)]
        $Command,
        [int] $MaxRetryCount = 4,
        [int] $RetryInterval = 4
    )

    $currErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $retryCount = 0
    while ($true) {
        try {
            $res = Invoke-Command -ScriptBlock $command
            $ErrorActionPreference = $currErrorActionPreference
            return $res
        } catch [System.Exception] {
            $retryCount++
            if ($retryCount -ge $maxRetryCount) {
                $ErrorActionPreference = $currErrorActionPreference
                throw
            } else {
                if($_) {
                Write-Warning $_
                }
                Start-Sleep $retryInterval
            }
        }
    }
}

function Mount-Share {
    param(
        [String] $SharedStoragePath,
        [String] $ShareUser,
        [String] $SharePassword
    )

    # Note(avladu): Sometimes, SMB mappings enter into an
    # "Unavailable" state and need to be removed, as they cannot be
    # accessed anymore.
    $smbMappingsUnavailable = Get-SmbMapping -RemotePath $SharedStoragePath `
        -ErrorAction SilentlyContinue | Where-Object {$_.Status -eq "Unavailable"}
    if ($smbMappingsUnavailable) {
        foreach ($smbMappingUnavailable in $smbMappingsUnavailable) {
            net use /delete $smbMappingUnavailable.LocalPath
        }
    }

    $mountPoint = $null
    $smbMapping = Get-SmbMapping -RemotePath $SharedStoragePath -ErrorAction SilentlyContinue
    if ($smbMapping) {
        if ($smbMapping.LocalPath -is [array]){
            return $smbMapping.LocalPath[0]
        } else {
            return $smbMapping.LocalPath
        }
    }
    if (!$ShareUser) {
        Write-Host "No share user provided"
        $auth = ""
    } else {
        $auth = "/u:`"AZURE\$ShareUser`" $SharePassword"
    }
    for ([byte]$c = [char]'G'; $c -le [char]'Z'; $c++) {
        $mountPoint = [char]$c + ":"
        try {
            net.exe use $mountPoint $SharedStoragePath $auth | Out-Null
            if ($LASTEXITCODE) {
                throw "Failed to mount share $SharedStoragePath to $mountPoint."
            } else {
                Write-Host "Successfully mounted SMB share on $mountPoint"
                return $mountPoint
            }
        } catch {
            Write-Host $_
        }
    }
    if (!$mountPoint) {
        Write-Host $Error[0]
        throw "Failed to mount $SharedStoragePath to $mountPoint"
    }
}

function Get-LisaCode {
    param(
        [parameter(Mandatory=$true)]
        [string] $LISAPath
    )
    if (Test-Path $LISAPath) {
        rm -Recurse -Force $LISAPath
    }
    git clone https://github.com/LIS/lis-test.git $LISAPath
}

function Copy-LisaTestDependencies {
    param(
        [parameter(Mandatory=$true)]
        [string[]] $TestDependenciesFolders,
        [parameter(Mandatory=$true)]
        [string] $LISARelPath,
        [parameter(Mandatory=$true)]
        [string] $LisaTestDependencies
    )

    # This function copies test dependencies in lisa folder
    # from a given share
    if (!(Test-Path $LisaTestDependencies)) {
        throw "${LisaTestDependencies} path does not exist!"
    }
    foreach ($folder in $TestDependenciesFolders) {
        $LisaDepPath = Join-Path $LisaTestDependencies $folder
        Copy-Item -Force `
            -Recurse -Path $LisaDepPath `
            -Destination $LISARelPath
    }
}

function Edit-TestXML {
    param(
        [parameter(Mandatory=$true)]
        [string] $Path,
        [parameter(Mandatory=$true)]
        [string] $VMSuffix,
        [string] $KeyName
    )
    $xmlFullPath = Join-Path $PWD $Path
    if (!(Test-Path $xmlFullPath)) {
        throw "Test XML $xmlFullPath does not exist."
    }
    $xml = [xml](Get-Content $xmlFullPath)
    $index = 0
    if ($xml.config.VMs.vm -is [array]) {
        foreach ($vmDef in $xml.config.VMs.vm) {
            $xml.config.VMS.vm[$index].vmName = $vmDef.vmName + $VMSuffix
            if ($KeyName) {
                $xml.config.VMS.vm[$index].sshKey = $KeyName
            }
            $testParams = $vmDef.testParams
            if ($testParams) {
                $paramIndex = 0
                foreach ($testParam in $testParams.param) {
                    if ($testParam -like "VM2NAME=*") {
                        $testParams.ChildNodes.Item($paramIndex)."#text" = `
                            $testParam + $VMSuffix
                    }
                    $paramIndex = $paramIndex + 1
                }
            }
            $index = $index + 1
        }
    } else {
        $xml.config.VMS.vm.vmName = $xml.config.VMS.vm.vmName + $VMSuffix
        if ($KeyName) {
            $xml.config.VMS.vm.sshKey = $KeyName
        }
    }
    $xml.Save($xmlFullPath)
}

function Remove-XmlVMs {
    param (
    [string] $Path,
    [string] $Suite
    )
    
    $xmlFullPath = Resolve-Path $Path
    $xml = [xml](Get-Content $xmlFullPath)
    if ($xml.config.VMs.vm -is [array]) {
        foreach ($vmDef in $xml.config.VMs.vm) {
            if ($vmDef.suite -eq $Suite){
                $TestVM = $vmDef
                $DependVMs = @($vmDef.vmName)
            }
        }
        if ($TestVM.testParams) {
            foreach ($param in $TestVM.testParams.param) {
                if ($param -like "VM2Name*"){
                    $DependVMs += @($param.split("=")[1])
                }
            }
        }
        foreach ($vmDef in $xml.config.VMs.vm) {
            if (!($DependVMs.contains($vmDef.vmName))) {
                $xml.config.VMs.removeChild($vmDef)
            }
        }
        $xml.Save($xmlFullPath)
    }
}

function Parse-IcaLog {
    param(
        [parameter(Mandatory=$true)]
        [String] $IcaLogPath
    )

    try {
        $allTestLines = [array](Get-Content $IcaLogPath | `
            Where-Object {$_ -match '(^Test\sResults\sSummary$)|(^\s\s\s\sTest\s)'})
        if (!$allTestLines) {
            throw "IcaLogPath $IcaLogPath does not contain test results summary."
        }
        $testLines = [array]($allTestLines | `
            Where-Object{$_ -match '(:\sFailed$)|(:\sAborted$)'})
        if ($testLines) {
            Write-Host "$testLines"
            return $testLines.Length
        } else {
            return 0
        }
    } catch {
        Write-Host "Failure to parse test results file."
        throw $_
    }
}

function Report-LisaResults {
    param(
        [parameter(Mandatory=$true)]
        [String] $PipelineName,
        [parameter(Mandatory=$true)]
        [String] $PipelineBuildNumber,
        [parameter(Mandatory=$true)]
        [String] $DBConfigPath,
        [parameter(Mandatory=$true)]
        [String] $IcaLogPath
    )

    $DB_RESULTS_REL_PATH = ".\tests.json"
    $PYTHON_PATH = Join-Path "${env:SystemDrive}" "Python27\python.exe"
    $RESULT_PARSER_PATH = Join-Path ${env:Workspace} "scripts\reporting\parser.py"

    $pipelineStageStatus = Parse-IcaLog -IcaLogPath $IcaLogPath
    $templateJSON = @'
[{{
        "PipelineName": "{0}",
        "PipelineBuildNumber": {1},
        "FuncTestsFailedOnLocal": {2}
}}]
'@
    $templateJSON = $templateJSON -f @($PipelineName,
           $PipelineBuildNumber, $pipelineStageStatus
       )

    Write-Host $templateJSON
    Write-Output $templateJSON | Out-File -Encoding ascii $DB_RESULTS_REL_PATH
    Copy-Item -Force $DBConfigPath $DB_CONFIG_REL_PATH
    & $PYTHON_PATH $RESULT_PARSER_PATH
}

Export-ModuleMember login_azure, make_cred, make_cred_initial,
    Assert-PathExists, Assert-URLExists, Execute-WithRetry, Mount-Share,
    Get-LisaCode, Copy-LisaTestDependencies, Edit-TestXML,
    Remove-XmlVMs, Parse-IcaLog, Report-LisaResults
