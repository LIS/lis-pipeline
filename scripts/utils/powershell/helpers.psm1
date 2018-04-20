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

function Mount-SMBShare {
    param(
        [String] $SharedStoragePath,
        [String] $ShareUser,
        [String] $SharePassword
    )

    # Note(avladu): Replace backslashes with forward slashes
    # for Windows compat
    $SharedStoragePath = $SharedStoragePath.replace('/', '\')

    # Note(avladu): Sometimes, SMB mappings enter into an
    # "Unavailable" state and need to be removed, as they cannot be
    # accessed anymore.
    $smbMappingsUnavailable = Get-SmbMapping -RemotePath $SharedStoragePath `
        -ErrorAction SilentlyContinue | `
        Where-Object {$_.Status -ne "Ok"}
    if ($smbMappingsUnavailable) {
        foreach ($smbMappingUnavailable in $smbMappingsUnavailable) {
            $output = net use /delete $smbMappingUnavailable.LocalPath 2>&1
        }
    }

    $mountPoint = $null
    $smbMapping = Get-SmbMapping -RemotePath $SharedStoragePath `
        -ErrorAction SilentlyContinue
    if ($smbMapping) {
        if ($smbMapping.LocalPath -is [array]){
            return $smbMapping.LocalPath[0]
        } else {
            return $smbMapping.LocalPath
        }
    }
    for ([byte]$c = [char]'G'; $c -le [char]'Z'; $c++) {
        $mountPoint = [char]$c + ":"
        try {
            $netOutput = net.exe use $mountPoint $SharedStoragePath `
                /u:"AZURE\$ShareUser" "$SharePassword" 2>&1
            if ($LASTEXITCODE) {
                throw ("Failed to mount share {0} to {1} with error {2}" `
                    -f @($SharedStoragePath, $mountPoint, $netOutput))
            } else {
                Get-PSDrive | Out-Null
                Get-SmbMapping | Out-Null
                return $mountPoint
            }
        } catch {
            if ($_ -like "*System error 67 has occurred.*") {
                throw $_
            }
        }
    }
    if (!$mountPoint) {
        Write-Host $Error[0]
        throw "Failed to mount $SharedStoragePath to $mountPoint"
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

Export-ModuleMember login_azure, make_cred, make_cred_initial,
    Assert-PathExists, Assert-URLExists, Execute-WithRetry, Mount-SMBShare,
    Parse-IcaLog, Get-LisaCode

