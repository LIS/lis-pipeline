#
#  Create a set of macines based on variants.  Variants are different machine types (standard_d2_v2), so a set of variant
#  machines all share the same base VHD image, but are (potentially) using different hardware configurations.#
#  Copies VHDs that have booted as expected to the test location where they will be prepped
#  for Azure automation
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $Flavors="",
    [Parameter(Mandatory=$false)] [string] $requestedNames = "",
    [Parameter(Mandatory=$false)] [string] $location = "",
    [Parameter(Mandatory=$false)] [string] $suffix = ""
)

$Flavors = $Flavors.Trim()
$requestedNames = $requestedNames.Trim()
$location = $location.Trim()
$suffix = $suffix.Trim()

[System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
if ($requestedNames -match ",") {
    $vmNameArray = $requestedNames.Split(',')
} else {
    $vmNameArray = $requestedNames
}

[System.Collections.ArrayList]$flavors_array
$flavorsArray = {$flavors_array}.Invoke()
$flavorsArray.Clear()
if ($Flavors -match ",") {
    $flavorsArray = $Flavors.Split(',')
} else {
    $flavorsArray = $Flavors
}

if ($flavorsArray.Count -eq 1 -and $flavorsArray[0] -eq "" ) {
    Write-Host "Must specify at least one VM Flavor to build..  Unable to process this request."
    exit 1
}

. "C:\Framework-Scripts\common_functions.ps1" > $null
. "C:\Framework-Scripts\secrets.ps1" > $null

$firstOne = $true
# Write-Verbose "Before the loop, names count is $allNamesCount"
# Write-Verbose "Before the loop, flavors count is $allFlavorsCount"
# Write-Verbose "listString = $listString"
foreach ($vmName in $vmNameArray) {
    $vmName = $vmName.Trim()
    # Write-Verbose "Setting flavors for |$vmName|"
    foreach ($oneFlavor in $flavorsArray) {
        $oneFlavor = $oneFlavor.Trim()

        # Write-Verbose "Adding the flavor information for $oneFlavor"
        $regionSuffix = ("---" + $location + "-" + $oneFlavor.ToLower()) -replace " ","-"
        $regionSuffix = $regionSuffix -replace "_","-"
        $imageName = $vmName + $regionSuffix
        $imageName = $imageName + $suffix
        $imageName = $imageName -replace ".vhd",""

        $theAddition = $imageName.Trim() 

        # write-verbose "Adding in |$theAddition|"

        if ($firstOne -eq $true) {
            $listString = $listString + $theAddition + ","
            # write-verbose "String is now |$listString|"
        } else {
            $listString = $theAddition + ","
            # write-verbose "String is now |$listString|"
            $firstOne = $true
        }
        # Write-Verbose "listString = $listString"
    }
}

# write-verbose "String is now |$listString|"
$listString = $listString -Replace ".$",""
# write-verbose "String is now |$listString|"

$listString.Trim()