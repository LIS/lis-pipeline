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
#   Description
#      This script extracts and parses the ubuntu linux-azure kernel version.
#      The linux-azure kernel version is saved in a text file and further
#      used to compare if a new version is available.
#      Only Ubuntu LTS releases are supported.
#
################################################################################

param (
    [String] $RemoteLocation,
    [String] $KernelParamFile,
    [String] $DistroParamFile
)

$URI_MAP = @{bionic_azure = "https://launchpad.net/ubuntu/bionic/+source/linux-azure";
             xenial_azure = "https://launchpad.net/ubuntu/xenial/+source/linux-azure";
             trusty_azure = "https://launchpad.net/ubuntu/trusty/+source/linux-azure";
             xenial_azure_edge = "https://launchpad.net/ubuntu/xenial/+source/linux-azure-edge";
             bionic_azure_edge = "https://launchpad.net/ubuntu/bionic/+source/linux-azure-edge";}
$CURL_PATH = "C:\PortableGit\mingw64\bin\curl.exe"

function Get-LatestPackageVersion {
    param (
        [String] $URI
    )
    [System.Object]$htmlObj = New-Object -ComObject "HTMLFile"
    $htmlFileName = "linux-azure.html"
    
    # Download the html file
    $downloadCommand = &${CURL_PATH} ${URI} --output ${htmlFileName}
    $srcBytes = [System.Text.Encoding]::Unicode.GetBytes($(Get-Content ${htmlFileName}))
    $htmlObj.write($srcBytes)

    # Get the latest version from the HTML file
    $innerText = $htmlObj.getElementById('maincontent').innerText
    $startPosition = $innerText.IndexOf("Current version: ") + 17
    $endPosition = $innerText.IndexOf("Uploaded:")

    # This is the latest kernel version as shown in launchpad
    Remove-Item -Force $htmlFileName
    [string] $launchpadVersion = $innerText.Substring($startPosition,$endPosition-$startPosition)
    return $launchpadVersion
}

function Write-VersionToShare {
    param (
        [String] $KernelVersion,
        [String] $Distro
    )

    # Get the latest known version
    $currentDir = (Get-Item -Path ".\").FullName
    Robocopy.exe $RemoteLocation $currentDir "latest-${Distro}.txt" /IS /IT /COPY:DAT /DCOPY:DAT /R:1 /S 2>&1
    if ($LASTEXITCODE -gt "7") {
        Write-Output "Robocopy failed to download latest-${Distro}.txt"
        return $false   
    }

    [string] $savedVersion = Get-Content "latest-${Distro}.txt"
    $savedVersion = $savedVersion -replace '\s',''
    $KernelVersion = $KernelVersion -replace '\s',''
    
    if ($savedVersion -eq $KernelVersion) {
        Write-Output "No new versions of ${Distro} kernel are avilable on launchpad" 
        return $true
    } else {
        Write-Output "New version available for ${Distro} kernel: $KernelVersion"
        Write-Output "Old version for ${Distro} kernel: $savedVersion"
        Set-Content -Value $KernelVersion -Path "latest-${Distro}.txt"
        Robocopy.exe $currentDir $RemoteLocation "latest-${Distro}.txt" /IS /IT /COPY:DAT /DCOPY:DAT /R:1 /S 2>&1
        if ($LASTEXITCODE -gt "7") {
            Write-Output "Robocopy failed to download latest-${Distro}.txt"
            return $false   
        }
        return $false
    }
}

function Main {
    # Get the version from launchpad
    $edgeKernelCounter = 0
    $azureKernelCounter = 0
    $distroToTest = New-Object System.Collections.Generic.List[System.Object]
    foreach ($distro in $URI_MAP.GetEnumerator()){
        $launchpadVersion = Get-LatestPackageVersion $distro.Value
        $sts = Write-VersionToShare $launchpadVersion $distro.Name
        if ($sts[-1] -eq $False) {
            Write-Output "$($distro.Name) has a new kernel"
            if ($distro.Name -match "edge") {
                $edgeKernelCounter++
            } else {
                $azureKernelCounter++
            }
            $distroToTest.Add($distro.Name)
        }
    }

    # Set the kernel to be tested
    if (($edgeKernelCounter -gt 0) -and ($azureKernelCounter -gt 0)) {
        "all" | Out-File -FilePath $KernelParamFile
    } elseIf (($edgeKernelCounter -eq 0) -and ($azureKernelCounter -gt 0)) {
        "linux-azure" | Out-File -FilePath $KernelParamFile
    } elseIf (($edgeKernelCounter -gt 0) -and ($azureKernelCounter -eq 0)) {
        "linux-azure-edge" | Out-File -FilePath $KernelParamFile
    } else {
        Write-Output "No new kernels are available"
        exit 1
    }

    # Set the distro to be tested
    foreach ($distro in $distroToTest) {
        if ($distro -match "trusty") {
            $testTrusty = $true
        } elseIf ($distro -match "xenial") {
            $testXenial = $true
        } elseIf ($distro -match "bionic") {
            $testBionic = $true
        }
    }
    if (($testTrusty -and $testXenial) -or ($testTrusty -and $testBionic) -or
        ($testXenial -and $testBionic)) {
        "all" | Out-File -FilePath $DistroParamFile
    } elseif ($testTrusty) {
        "trusty" | Out-File -FilePath $DistroParamFile
    } elseif ($testXenial) {
        "xenial" | Out-File -FilePath $DistroParamFile 
    } elseif ($testBionic) {
        "bionic" | Out-File -FilePath $DistroParamFile 
    }

    exit 0
}

Main