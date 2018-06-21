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
#
#
################################################################################

param (
    [String] $RemoteLocation
)

$URI_MAP = @{bionic_azure = "https://launchpad.net/ubuntu/bionic/+source/linux-azure";
             xenial_azure = "https://launchpad.net/ubuntu/xenial/+source/linux-azure";}

function Get-LatestPackageVersion {
    param (
        [String] $URI
    )

    # Get the latest version from the HTML file
    $htmlData = Invoke-WebRequest -Uri $URI
    $innerText = $htmlData.ParsedHtml.getElementById('maincontent').innerText
    $startPosition = $innerText.IndexOf("Current version: ") + 17
    $endPosition = $innerText.IndexOf(" Uploaded:")

    # This is the latest kernel version as shown in launchpad
    [string] $launchpadVersion = $innerText.Substring($startPosition,$endPosition-$startPosition)
    return $launchpadVersion
}

function Write-VersionToShare {
    param (
        [String] $KernelVersion,
        [String] $Distro
    )

    [string] $savedVersion = Get-Content "${RemoteLocation}\latest-${Distro}.txt"
    if ($savedVersion -eq $KernelVersion) {
        Write-Output "No new versions of ${Distro} kernel are avilable on launchpad" 
        return $true
    } else {
        Write-Output "New version available for ${Distro} kernel: $KernelVersion"
        Write-Output "Old version for ${Distro} kernel: $savedVersion"
        Set-Content -Value $KernelVersion -Path "${RemoteLocation}\latest-${Distro}.txt"
        return $false
    }
}

function Main {
    # Get the version from launchpad 
    $changeTable = @{}
    foreach ($distro in $URI_MAP.GetEnumerator()){
        $launchpadVersion = Get-LatestPackageVersion $distro.Value
        $sts = Write-VersionToShare $launchpadVersion $distro.Name
        $changeTable.Add($distro.Name, $sts[-1])
    }
    
    if (($changeTable.xenial_azure -eq $False) -and ($changeTable.bionic_azure -eq $False)) {
        Write-Output "New kernel available for Bionic and Xenial. Triggering testing for both"
        exit 1
    } elseIf ($changeTable.xenial_azure -eq $False) {
        Write-Output "New kernel available for Xenial. Triggering testing"
        exit 2
    } elseIf ($changeTable.bionic_azure -eq $False) {
        Write-Output "New kernel available for Bionic. Triggering testing"
        exit 3
    } else {
        Write-Output "No new kernels are available"
        exit 0
    }
}

Main
