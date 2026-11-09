@{
    "check" = {
        Write-Host "Checking style inside $($PWD.Path)"
        return @{
            pwd = $PWD.Path
        }
    }
    "fix"   = {
        Write-Host "Fixing style inside $($PWD.Path)"
    }
}
