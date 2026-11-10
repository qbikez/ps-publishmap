@{
    "top-level" = {
        Write-Host "top level task"
    }
    # A #include key ending in .ps1 loads that map file instead of <dir>/.build.map.ps1,
    # so one directory can hold several maps. Paths are relative to this map.
    # Entries run in the included file's directory (tools/).
    "#include"  = @{
        # entries appear as lint.<entry> (file name without .build.map.ps1)
        "tools/lint.build.map.ps1"    = @{
            prefix = $true
        }
        # entries are merged into this map
        "tools/release.build.map.ps1" = @{
            prefix = $false
        }
    }
}
