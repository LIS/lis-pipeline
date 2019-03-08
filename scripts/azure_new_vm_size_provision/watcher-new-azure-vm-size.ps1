param (
    $LisaPath,
    $NewFile,
    $OldFile,
    $VmOutputFile,
    $SecretsFile,
    $CustomSecretsFilePath
)

function Main {

$HtmlStart = '
<style type="text/css">
.tg  {border-collapse:collapse;border-spacing:0;border-color:#999;}
.tg td{font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#999;color:#444;background-color:#F7FDFA;}
.tg th{font-family:Arial, sans-serif;font-size:14px;font-weight:normal;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#999;color:#fff;background-color:#26ADE4;}
.tg .tg-baqh{text-align:left;vertical-align:top}
.tg .tg-lqy6{text-align:left;vertical-align:top}
.tg .tg-yw4l{vertical-align:top}
.tg .tg-amwmleft{text-align:left;font-weight:bold;vertical-align:top}
</style>
<table class="tg">
  <tr>
    <th class="tg-amwmleft">SR. #</th>
    <th class="tg-amwmleft">Region</th>
    <th class="tg-amwmleft">Size</th>
    <th class="tg-amwmleft">Added/Removed</th>    
  </tr>
'

$HtmlRow = '
  <tr>
    <td class="tg-yw4l">NEWSERIAL</td>
    <td class="tg-baqh">NEWREGION</td>
    <td class="tg-lqy6">NEWSIZE</td>
    <td class="tg-lqy6">ADDREMOVESTATUS</td>
  </tr>
'
$HtmlEnd = '</table><p style="text-align: right;"><em><span style="font-size: 18px;"><span style="font-family: times new roman,times,serif;">&gt;</span></span></em></p>'

    if ( $customSecretsFilePath ) {
        $secretsFile = $customSecretsFilePath
        Write-Host "Using provided secrets file: $($secretsFile | Split-Path -Leaf)"
    }
    if ( $secretsFile -eq $null ) {
        Write-Host "ERROR: Azure Secrets file not found in Jenkins / user not provided -customSecretsFilePath" -ForegroundColor Red -BackgroundColor Black
        exit 1
    }


    if ( Test-Path $secretsFile) {
        Write-Host "$($secretsFile | Split-Path -Leaf) found."
        $xmlSecrets = [xml](Get-Content $secretsFile)
        $LogFileName = "AddAzureRmAccountFromSecretsFile.log"
        Set-Variable -Name LogFileName -Value $LogFileName -Scope Global -Force
        Resolve-Path ${LisaPath}
        & ${LisaPath}\Utilities\AddAzureRmAccountFromSecretsFile.ps1 -customSecretsFilePath $secretsFile
        $subscriptionID = $xmlSecrets.secrets.SubscriptionID
    }
    else {
        Write-Host "$($secretsFile | Split-Path -Leaf) file is not added in Jenkins Global Environments OR it is not bound to 'Azure_Secrets_File' variable." -ForegroundColor Red -BackgroundColor Black
        Write-Host "Aborting." -ForegroundColor Red -BackgroundColor Black
        exit 1
    }

    Write-Host "Getting regions"
    Remove-Item -Path $OldFile -Verbose -Force
    Copy-Item -Path $NewFile -Destination $OldFile -Verbose -Force
    Remove-Item -Path $NewFile -Force -Verbose
    $allRegions = (Get-AzureRMLocation | Where-Object {$_.Providers.Contains("Microsoft.Compute")}).Location
    foreach ( $region in $allRegions) {
        try {
            Write-Host "Getting VM sizes from $region"
            $vmSizes = Get-AzureRmVMSize -Location $region
            foreach ( $vmSize in $vmSizes ) {
                Add-Content -Value "$region $($vmSize.Name)" -Path $NewFile -Force
            }
        }
        catch {
            Write-Error "Failed to fetch data from $region."
        }
    }

    $newVMSizes = Compare-Object -ReferenceObject (Get-Content -Path $OldFile ) -DifferenceObject (Get-Content -Path $NewFile)
    $newVMs = 0
    $newVMsString = $null
    $HeaderAdded = $false
    $HtmlReportString = ""
    foreach ( $newSize in $newVMSizes ) {
        if ( $newSize.SideIndicator -eq '=>') {
            if (-not $HeaderAdded) {
                $HtmlReportString += "$HtmlStart`n"
                $HeaderAdded = $true
            }
            $newVMs += 1
            $CurrentRegion = $newSize.InputObject.Split(" ")[0]
            $CurrentSize = $newSize.InputObject.Split(" ")[1]
            $CurrentRow  = $HtmlRow
            $CurrentRow = $CurrentRow.Replace("NEWSERIAL","$newVMs")
            $CurrentRow = $CurrentRow.Replace("NEWREGION","$CurrentRegion")
            $CurrentRow = $CurrentRow.Replace("NEWSIZE","$CurrentSize")
            $CurrentRow = $CurrentRow.Replace("ADDREMOVESTATUS","Added")
            $HtmlReportString += $CurrentRow
            Write-Host "$newVMs. $($newSize.InputObject) Added"
        }
        elseif ($newSize.SideIndicator -eq '<=') {
            if (-not $HeaderAdded) {
                $HtmlReportString += "$HtmlStart`n"
                $HeaderAdded = $true
            }
            $newVMs += 1
            $CurrentRegion = $newSize.InputObject.Split(" ")[0]
            $CurrentSize = $newSize.InputObject.Split(" ")[1]
            $CurrentRow  = $HtmlRow
            $CurrentRow = $CurrentRow.Replace("NEWSERIAL","$newVMs")
            $CurrentRow = $CurrentRow.Replace("NEWREGION","$CurrentRegion")
            $CurrentRow = $CurrentRow.Replace("NEWSIZE","$CurrentSize")
            $CurrentRow = $CurrentRow.Replace("ADDREMOVESTATUS","Removed")
            $HtmlReportString += $CurrentRow
            Write-Host "$newVMs. $($newSize.InputObject) Removed"
        }
    }
    if ( $newVMs -eq 0) {
        Write-Host "No New sizes today."
        Set-Content -Value "NO_NEW_VMS" -Path $VmOutputFile -NoNewline
    }
    else {
        $HtmlReportString += $HtmlEnd
        Set-Content -Value $HtmlReportString -Path $VmOutputFile -NoNewline
    }
    Write-Host "Exiting with zero"
    exit 0
}
Main