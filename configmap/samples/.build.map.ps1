# Aggregates every sample under a prefix, e.g. `qbuild build.<entry>`, `qbuild write.write:simple`.
# Mirrors the `samples` perf fixture (test/perf/New-PerfFixture.ps1), which generates the same map.
[ordered]@{
    "#include" = [ordered]@{
        "build"         = @{ prefix = $true }
        "concurrent"    = @{ prefix = $true }
        "dir-context"   = @{ prefix = $true }
        "dotenv"        = @{ prefix = $true }
        "hierarchical"  = @{ prefix = $true }
        "include"       = @{ prefix = $true }
        "pkg"           = @{ prefix = $true }
        "playwright"    = @{ prefix = $true }
        "process-mixed" = @{ prefix = $true }
        "write"         = @{ prefix = $true }
    }
}
