@{
    "publish" = {
        param([string]$Version = "0.0.1")
        Write-Host "Publishing $Version inside $($PWD.Path)"
    }
}
