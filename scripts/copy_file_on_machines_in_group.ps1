param (
    [Parameter(Mandatory=$false)] [string[]] $requestedNames,
    
    [Parameter(Mandatory=$false)] [string] $destSA="smokesrc",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string] $suffix="-Runonce-Primed.vhd",

    [Parameter(Mandatory=$false)] [string] $scriptName="unset",

    [Parameter(Mandatory=$false)] [int] $retryCount=2 
)

$destSA = $destSA.Trim()
$destRG = $destRG.Trim()
$location = $location.Trim()
$suffix = $suffix.Trim()
$scriptName = $scriptName.Trim()

$suffix = $suffix -replace "_","-"
    
. c:\Framework-Scripts\common_functions.ps1
. c:\Framework-Scripts\secrets.ps1

[System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
if ($requestedNames -like "*,*") {
    $vmNameArray = $requestedNames.Split(',')
} else {
    $vmNameArray = $requestedNames
}

write-Verbose "Copying file $file to $vmNameArray "

#
#  Session stuff
#
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$cred = make_cred

$password="$TEST_USER_ACCOUNT_PASS"

$command="cp -f /HIPPEE/Framework-Scripts/" + $scriptName + " /HIPPEE/runonce.d"
$runCommand = "echo $password | sudo -S bash -c `'$command`'"

$commandBLock=[scriptblock]::Create($runCommand)

foreach ($baseName in $vmNameArray) {
    $vm_name = $baseName
    [int]$timesTried = 0
    [bool]$success = $false
    while ($timesTried -lt $retryCount) {
        Write-Verbose "Executing copy command on machine $vm_name, resource gropu $destRG"
        $timesTried = $timesTried + 1
            Write-Verbose "Executing copy command on machine $vm_name"
            [System.Management.Automation.Runspaces.PSSession]$session = create_psrp_session $vm_name $destRG $destSA $location $cred $o
            if ($? -eq $true -and $session -ne $null) {
                invoke-command -session $session -ScriptBlock $commandBLock -ArgumentList $runCommand
            } else {
                Write-Error "    FAILED to establish PSRP connection to machine $vm_name."
                Remove-PSSession $session
            }
        }
        Start-Sleep -Seconds 10
    }
