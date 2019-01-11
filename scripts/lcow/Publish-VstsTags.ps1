param (
    [String] $RestToken ,
    [String] $BaseUrl, 
    [String] $BuildID,
    [String] $Tags
)

function Main {
    $token = ":$($RestToken)"
    $encodedToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($token))
    $encodedToken = "Basic $encodedToken"
    
    foreach ($tag in $Tags.Split(";")) {
        if ($tag != $null) {
            $url = "${BaseUrl}/${BuildID}/tags/${tag}?api-version=5.0-preview.2"
            Invoke-RestMethod -Uri $url -Headers @{Authorization = $encodedToken}  -Method Put
        }
    }
}

Main