[ordered]@{
    "clean"    = { Write-Host "clean" }
    "restore"  = @{ exec = { param([switch]$Force) Write-Host "restore" }; description = "Restore everything" }
    "#include" = [ordered]@{
        "p01" = @{ prefix = $true }
        "p02" = @{ prefix = $true }
        "p03" = @{ prefix = $true }
        "p04" = @{ prefix = $true }
        "p05" = @{ prefix = $true }
    }
}
