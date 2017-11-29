param (
    [Parameter(Mandatory=$false)] [string] $requestedName="Unset",
    
    [Parameter(Mandatory=$false)] [string] $destSA="smokesrc",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",

    [Parameter(Mandatory=$false)] [string] $suffix="-Runonce-Primed.vhd",

    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [int] $retryCount=2
)
    
$destSA = $destSA.Trim()
$destRG = $destRG.Trim()
$suffix = $suffix.Trim()
$location = $location.Trim()

. c:\Framework-Scripts\common_functions.ps1
. c:\Framework-Scripts\secrets.ps1

if ($requestedNames -like "*,*") {
    Write-Error "create_session_to_machine does not take more than one machine parameter."
    exit 1
} else {
    $vm_name += $requestedName
}

$suffix = $suffix -replace "_","-"

. C:\Framework-Scripts\common_functions.ps1
. C:\Framework-Scripts\secrets.ps1

$logName = "C:\temp\transcripts\create_session_to_machine-" + $requestedName + "-" + (Get-Date -Format s).replace(":","-")
Start-Transcript -path $logName -force

login_azure $DestRG $DestSA $location > $null
#
#  Session stuff
#
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$cred = make_cred

$suffix = $suffix.Replace(".vhd","")

[int]$timesTried = 0
[bool]$success = $false
while ($timesTried -lt $retryCount) {
    write-verbose  "Creating PSRP session to remote machine $vm_name, resource group $destRG"
    $timesTried = $timesTried + 1

    [System.Management.Automation.Runspaces.PSSession]$session = create_psrp_session $vm_name $destRG $destSA $location $cred $o
    if ($? -eq $true -and $session -ne $null) {
        Enter-PSSession -Session $session
        $success = $true
        break
    } else {
        if ($timesTried -lt $retryCount) {
            Write-Host "    Try $timesTried of $retryCount -- FAILED to establish PSRP connection to machine $vm_name."
        }
    }
    start-sleep -Seconds 10
}
    
# Stop-Transcript > $null

if ($success -eq $true) {
    exit 0
} else {
    exit 1
}