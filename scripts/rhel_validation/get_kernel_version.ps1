################################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
################################################################################

################################################################################
#
#	Description
#
#	This script will check if new version of kernel exists for each version of Redhat.
#	This script imports the login cookies for downloading the html to get 
# the entire list of kernels. For each version of Redhat it creates a list with 
# kernels associated and stores these informations in a hash table.
#	Each version of Redhat has a latest kernel stored in a file which is compared 
# with the last added kernel in hash table.
#
################################################################################

param (
    [String] $WorkDir,
    [String] $LatestVersionsFile,
    [String] $OutputFile,
    [String] $RemoteHtmlLocation,
    [String] $UtilsDir,
    [String] $RepoListOutFile
)

# generate hash table with list of kernels for each version of rhel
$RHEL_VERSIONS_TO_KERNEL_MAP = @{"rhel_6.7" = @{"baseVer" = "2.6.32-573"; "newVer" = @()};
                                 "rhel_6.8" = @{"baseVer" = "2.6.32-642"; "newVer" = @()};
                                 "rhel_6.9" = @{"baseVer" = "2.6.32-696"; "newVer" = @()};
                                 "rhel_6.10" = @{"baseVer" = "2.6.32-754"; "newVer" = @()};
                                 "rhel_7.3" = @{"baseVer" = "3.10.0-514"; "newVer" = @()};
                                 "rhel_7.4" = @{"baseVer" = "3.10.0-693"; "newVer" = @()};
                                 "rhel_7.5" = @{"baseVer" = "3.10.0-862"; "newVer" = @()};
                                 "rhel_7.6" = @{"baseVer" = "3.10.0-957"; "newVer" = @()}}

function Get-StoredVersions {
    param (
        [String] $LatestVersionsFile
    )
    
    if (Test-Path $LatestVersionsFile) {
        $latestVersions = (Get-Content $LatestVersionsFile).Split(";")
        foreach ($latestVersion in $latestVersions) {
            if ($latestVersion) {
                $distro = $latestVersion.split("=")[0].Trim()
                $kernel = $latestVersion.split("=")[1].Trim()
                $latestVersionsHash += @{$distro = $kernel}
            }
        }
    } else {
        New-Item -Path $LatestVersionsFile -Force | Out-Null
        $latestVersionsHash = @{}
    }
    
    return $latestVersionsHash
}

function Get-VersionsHtml {
    param (
        [String] $HtmlPath,
        [String] $RemoteUrl,
        [String] $CookiePath
    )
    
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $contentCookies = (Get-Content -Raw $CookiePath | ConvertFrom-Json)
    # add session cookies
    foreach($cook in $contentCookies) { 
        $cookie = New-Object System.Net.Cookie 
        $cookie.Name=$cook.name
        $cookie.Domain = $cook.domain
        $cookie.Value = $cook.value
        $cookie.Expires = '1/12/2050 12:04:12 AM' 
        $session.Cookies.Add($cookie);
    }
    # downloading page
    Write-Host "Downloading kernel page..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest $RemoteUrl -WebSession $session -UseBasicParsing -TimeoutSec 900 -OutFile $HtmlPath
    Start-Sleep 20
}

function Parse-Html {
    param (
        [Hashtable] $BaseHash,
        [String] $HtmlPath
    )
    
    # get list of kernel version rhel
    Write-Host "Generating list.."
    $html = New-Object -ComObject "HTMLFile"
    $source = Get-Content -Path $HtmlPath -Raw
    $source = [System.Text.Encoding]::Unicode.GetBytes($source)
    $html.write($source)
    $content=$html.body.getElementsByTagName('select')
    $content = $content[1].textContent.Split()

    foreach ($entry in $content) {
        foreach ($key in $BaseHash.Keys) {
            $baseVer = $BaseHash[$key]["baseVer"] 
            if ($entry -match "$baseVer*") {
                $BaseHash[$key]["newVer"] += $entry
            }
        }
    }
    
    return $BaseHash
}

function Get-UpdatedVersionsList {
    param (
        [Hashtable] $NewHash,
        [Hashtable] $LatestHash
    )
    
    foreach ($key in $NewHash.Keys) {
        if ($NewHash[$key]["newVer"] -and ($NewHash[$key]["newVer"][0] -ne $LatestHash[$key])){
            $resultList += @("{0}={1};" -f @($key, $NewHash[$key]["newVer"][0]))
            $LatestHash[$key] = $NewHash[$key]["newVer"][0]
        }
        $latestVersionsList += @("{0}={1};" -f @($key, $LatestHash[$key]))
    }
    
    return $resultList, $latestVersionsList
}

Function Get-KernelRepositoryName {
    param (
        [string] $Kernel_link,
        [string] $kernelhtmlRepo,
        [string] $CookiePath
    )

    $RepoList=''
    $isTextDetected = $false
    $isTableDetected = $false
    $PrefixURL = "https://access.redhat.com"
    $fullURL = $PrefixURL + $Kernel_link
    Get-VersionsHtml -HtmlPath $kernelhtmlRepo -RemoteUrl $fullURL -CookiePath  $CookiePath
    $RepoData = Get-Content -Path $kernelhtmlRepo -Raw
    foreach ($line in $RepoData.split("`n")) {
        if ($line -imatch "Repos shown are based on your active subscriptions") {
            $isTextDetected = $true
        }
        if ($line -imatch "<table") {
            $isTableDetected = $true
        }
        if ($isTextDetected -and $isTableDetected ) {
            if ($line -imatch '</table>') {
                break;
            }
            if ($line -imatch '<br') {
                $RepoList += $line.Trim().Split("<")[0].Trim() + "^"
            }
        }
    }
    return $RepoList
}

################################################################################
#
# Main script body
#
################################################################################
function Main {
    if (!(Test-Path $WorkDir)) {
        New-Item -Type Directory -Path $WorkDir
    }
    $htmlPath = Join-Path $WorkDir "package.html"
    if (Test-Path $htmlPath) {
        Remove-Item  $htmlPath
    }
    New-Item -Path $OutputFile -Force
    $OutputFile = Resolve-Path $OutputFile
    
    New-Item -Path $RepoListOutFile -Force
    $RepoListOutFile = Resolve-Path $RepoListOutFile

    $latestVersionsHash = Get-StoredVersions -LatestVersionsFile $LatestVersionsFile
    
    Push-Location $WorkDir
    $cookiePath = Join-Path $UtilsDir "cookies_redhat.json"
    Get-VersionsHtml -HtmlPath ".\package.html" -RemoteUrl $RemoteHtmlLocation -CookiePath $cookiePath

    $hash = Parse-Html -BaseHash $RHEL_VERSIONS_TO_KERNEL_MAP -HtmlPath ".\package.html"
    $resultList, $latestVersionsList = Get-UpdatedVersionsList -NewHash $hash -LatestHash $latestVersionsHash

    if ($resultList) {
        Write-Output "${resultList}" | Out-File $OutputFile
        $kernelVersions = ($resultlist -replace "rhel_\d+.\d+=","").Split(";").trim()
        foreach ($kernel in $kernelVersions) {
            if ($kernel) {
                $kernelhtmlpath=Get-Content -Path ".\package.html" | `
                          where { $_ | Select-String -Pattern $kernel } | `
                          where { $_ | Select-String -Pattern 'x86_64' } | `
                          where { $_ | Select-String -Pattern 'value="(.*)"' }
                $kernelpath=$kernelhtmlpath.ToString().Trim() -replace 'value=',"" -replace '\"',''
                $RepoList=Get-KernelRepositoryName -CookiePath $cookiePath -Kernel_link $kernelpath -kernelhtmlRepo "repo.html"
                $ResultRepoList += @("{0}={1};" -f @($kernel, $RepoList))
            }
        }
        Write-Output "${ResultRepoList}" | Out-File $RepoListOutFile
    } else {
        Write-Output "No new kernel versions were found"
    }
    if ($latestVersionsList) {
        Write-Output "${latestVersionsList}" | Out-File $LatestVersionsFile
    } else {
        Write-Output "Error saving the list with latest kernel versions"
        exit 1
    }
}

Main
