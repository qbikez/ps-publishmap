@{
    "top-level" = {
        Write-Host "top level task"
    }
    # Child maps are loaded lazily, only when an entry under them is resolved or listed.
    # Their entries run in the child map's directory.
    "#include"  = @{
        # child/.build.map.ps1 entries appear as child.<entry>
        "child"  = @{
            prefix = $true
        }
        # shared/.build.map.ps1 entries are merged into this map
        "shared" = @{
            prefix = $false
        }
    }
}
