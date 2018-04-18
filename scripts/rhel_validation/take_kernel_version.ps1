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
#	This script will find out if new kernel exists for each version of Redhat
# from RHEL6.0 to RHEL7.4.
#	This script imports the login cookies for downloading the html to get 
# the entire list of kernels. For each version of Redhat it creates a list with 
# kernels associated and stores these informations in a hash table.
#	Each version of Redhat has a latest kernel stored in a file which is compared 
# with the last added kernel in hash table.
#
################################################################################
################################################################################
#
# Main script body
#
################################################################################

param (
    [String] $WorkDir,
    [String] $LatestVersionFile,
    [String] $KernelVersionsPath,
    [String] $UtilsDir
)

if (!(Test-Path $WorkDir)) {
    New-Item -Type Directory -Path $WorkDir
}
if (Test-Path "$WorkDir\package.html") {
    Remove-Item  "$WorkDir\package.html"
}
New-Item -Path $KernelVersionsPath -Force
$KernelVersionsPath = Resolve-Path $KernelVersionsPath

if (Test-Path $LatestVersionFile) {
    $LatestVersions = Get-Content $LatestVersionFile
    $LatestVersions = $LatestVersions.Split(";")
    foreach ($entry in $LatestVersions) {
        if ($entry) {
            $distro = $entry.split("=")[0]
            $kernel = $entry.split("=")[1]
            $LatestVersionsHash += @{$distro = $kernel}
        }
    }
} else {
    Write-Host "No versions file found. Creating a new one"
    New-Item -Path $LatestVersionFile -Force
}
Copy-Item "$UtilsDir\cookies_redhat.json" $WorkDir

# generate hash table with list of kernels for each version of rhel
$hash = @{"rhel_7.4" = @{"baseVer" = "3.10.0-693"; "newVer" = @()}; 
    "rhel_7.3" = @{"baseVer" = "3.10.0-514", "newVer" = @()}; 
    "rhel_7.2" = @{"baseVer" = "3.10.0-327", "newVer" = @()}; 
    "rhel_7.1" = @{"baseVer" = "3.10.0-229", "newVer" = @()}; 
    "rhel_7.0" = @{"baseVer" = "3.10.0-123", "newVer" = @()}; 
    "rhel_6.9" = @{"baseVer" = "2.6.32-696", "newVer" = @()}; 
    "rhel_6.8" = @{"baseVer" = "2.6.32-642", "newVer" = @()}; 
    "rhel_6.7" = @{"baseVer" = "2.6.32-573", "newVer" = @()}; 
    "rhel_6.6" = @{"baseVer" = "2.6.32-504", "newVer" = @()}; 
    "rhel_6.5" = @{"baseVer" = "2.6.32-431", "newVer" = @()}; 
    "rhel_6.4" = @{"baseVer" = "2.6.32-358", "newVer" = @()}; 
    "rhel_6.3" = @{"baseVer" = "2.6.32-279", "newVer" = @()}; 
    "rhel_6.2" = @{"baseVer" = "2.6.32-220", "newVer" = @()}; 
    "rhel_6.1" = @{"baseVer" = "2.6.32-131", "newVer" = @()}; 
    "rhel_6.0" = @{"baseVer" = "2.6.32-71", "newVer" = @()};
}

pushd $WorkDir
$downloadToPath = "package.html"
$remoteFileLocation = "https://access.redhat.com/downloads/content/kernel/2.6.32-642.15.1.el6/x86_64/fd431d51/package"
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$content_cookies=(Get-Content -Raw .\cookies_redhat.json | ConvertFrom-Json)

# add cookies for our session
foreach($cook in $content_cookies) { 
    $cookie = New-Object System.Net.Cookie 
    $cookie.Name=$cook.name
    $cookie.Domain = $cook.domain
    $cookie.Value = $cook.value
    $cookie.Expires = '1/12/2050 12:04:12 AM' 
    $session.Cookies.Add($cookie);
}

# downloading page
Write-Host "Downloading.."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest $remoteFileLocation -WebSession $session -UseBasicParsing -TimeoutSec 900 -OutFile $downloadToPath
Start-Sleep 20

# testing
Get-Content -Path ".\package.html" -Raw

# get list of kernel version rhel
Write-Host "Generating list.."
$html = New-Object -ComObject "HTMLFile"
$source = Get-Content -Path ".\package.html" -Raw
$source = [System.Text.Encoding]::Unicode.GetBytes($source)
$html.write($source)
$content=$html.body.getElementsByTagName('select')
$content = $content[1].textContent.Split()

# testing
Write-Host $content

foreach ($entry in $content) {
    for ($key in $hash.Keys) {
        $baseVer = $hash[$key]["baseVer"] 
        if ($entry -match "$baseVer*") {
            $hash[$key]["newVer"] += $entry
        }
    }
}

foreach ($key in $hash.Keys) {
    if ($hash[$key]["newVer"] -and ($hash[$key]["newVer"][0] -nomatch $LatestVersionsHash[$key])){
        Write-Output ("New kernel {0}: {1}`nPrevious kernel {0}: {2}" -f
            @($key, $hash[$key]["newVer"][0], $LatestVersionsHash[$key]))
        $resultList += @("{0}={1};" -f @($key, hash[$key]["newVer"][0]))
        $LatestVersionsHash[$key] = $hash[$key]["newVer"][0]
    }
    $latestVersionsList += @("{0}={1};" -f @($key, $LatestVersionsHash[$key]))
}

# testing
$resultList = "rhel_7.4=3.10.0-693.21.1.el7;rhel_7.3=3.10.0-693.21.1.el7"
$latestVersionsList = "rhel_7.4=3.10.0-693.21.1.el7;rhel_7.3=3.10.0-693.21.1.el7"

if ($resultList) {
    Write-Output $resultList | Out-File $KernelVersionsPath
} else {
    Write-Output "Error writing resultList"
    exit 1
}
if ($latestVersionsList) {
    Write-Output $latestVersionsList | Out-File $LatestVersionFile
} else {
    Write-Output "Error writing latestVersionsList"
    exit 1
}

Write-Host "Completed!"
return $True