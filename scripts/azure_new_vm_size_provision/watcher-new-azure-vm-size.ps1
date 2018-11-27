param (
    $LisaPath,
    $NewFile,
    $OldFile,
    $VmOutputFile,
    $SecretsFile,
    $CustomSecretsFilePath
)

function Main {
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
    foreach ( $newSize in $newVMSizes ) {
        if ( $newSize.SideIndicator -eq '=>') {
            $newVMs += 1
            Write-Host "$newVMs. $($newSize.InputObject)"
            $newVMsString += "$($newSize.InputObject),"
        }
        else {
            Write-Host "$newVMs. $($newSize.InputObject) $($newSize.SideIndicator)"
        }
    }
    if ( $newVMs -eq 0) {
        Write-Host "No New sizes today."
        Set-Content -Value "NO_NEW_VMS" -Path $VmOutputFile -NoNewline
    }
    else {
        Set-Content -Value $($newVMsString.TrimEnd(",")) -Path $VmOutputFile -NoNewline
    }
    Write-Host "Exiting with zero"
    exit 0
}
Main