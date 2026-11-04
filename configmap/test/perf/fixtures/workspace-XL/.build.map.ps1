[ordered]@{
    "clean" = { Write-Host "clean" }
    "restore" = @{ exec = { param([switch]$Force) Write-Host "restore" }; description = "Restore everything" }
    "#include" = [ordered]@{
        "p01" = @{ prefix = $true }
        "p02" = @{ prefix = $true }
        "p03" = @{ prefix = $true }
        "p04" = @{ prefix = $true }
        "p05" = @{ prefix = $true }
        "p06" = @{ prefix = $true }
        "p07" = @{ prefix = $true }
        "p08" = @{ prefix = $true }
        "p09" = @{ prefix = $true }
        "p10" = @{ prefix = $true }
        "p11" = @{ prefix = $true }
        "p12" = @{ prefix = $true }
        "p13" = @{ prefix = $true }
        "p14" = @{ prefix = $true }
        "p15" = @{ prefix = $true }
        "p16" = @{ prefix = $true }
        "p17" = @{ prefix = $true }
        "p18" = @{ prefix = $true }
        "p19" = @{ prefix = $true }
        "p20" = @{ prefix = $true }
        "p21" = @{ prefix = $true }
        "p22" = @{ prefix = $true }
        "p23" = @{ prefix = $true }
        "p24" = @{ prefix = $true }
        "p25" = @{ prefix = $true }
        "p26" = @{ prefix = $true }
        "p27" = @{ prefix = $true }
        "p28" = @{ prefix = $true }
        "p29" = @{ prefix = $true }
        "p30" = @{ prefix = $true }
        "p31" = @{ prefix = $true }
        "p32" = @{ prefix = $true }
        "p33" = @{ prefix = $true }
        "p34" = @{ prefix = $true }
        "p35" = @{ prefix = $true }
        "p36" = @{ prefix = $true }
        "p37" = @{ prefix = $true }
        "p38" = @{ prefix = $true }
        "p39" = @{ prefix = $true }
        "p40" = @{ prefix = $true }
    }
}

