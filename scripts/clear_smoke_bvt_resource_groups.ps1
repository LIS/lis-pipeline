. C:\Framework-Scripts\common_functions.ps1

login_azure "smoke_source_resource_group" "smokesrc" "westus"

$names=(Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -like "ICA-RG-*Smoke*"}).ResourceGroupName
get-job | Remove-Job

foreach ($name in $names) {
    $scriptText = " . `"C:\Framework-Scripts\common_functions.ps1`" `
                    login_azure `"smoke_source_resource_group`" `"smokesrc`" `"westus`" `
                    Remove-AzureRmResourceGroup -ResourceGroupName $name -force"
    $scriptBlock=[scriptblock]::Create($scriptText)
    start-job -ScriptBlock $scriptBlock
}