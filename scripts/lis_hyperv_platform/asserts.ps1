function Assert-PathExists {
    param(
        [String] $Path
    )
    if (!(Test-Path $Path)) {
       throw "Path $Path not found"
    }

}

function Assert-URLExists {
    param(
        [String] $URL
    )

    Write-Host "Checking Kernel URL"
    $httpRequest = [System.Net.WebRequest]::Create($URL)
    $httpResponse = $httpRequest.GetResponse()
    $httpStatus = [int]$httpResponse.StatusCode

    if ($httpStatus -ne 200) {
        Write-Host "The Site may be down, please check!"
        throw "Kernel URL can't be reached!"
    }

    $httpResponse.Close()
}

