# Same entries as samples/include, built by dot-sourcing the child maps instead of #include.
# Every child map is evaluated each time this map is loaded, and their entries run in
# this map's directory (use $PSScriptRoot inside a child script for its own directory).
$child = . "$PSScriptRoot/child/.build.map.ps1"
$shared = . "$PSScriptRoot/shared/.build.map.ps1"

$map = @{
    "top-level"     = {
        Write-Host "top level task"
    }
    # Nested under a key: entries appear as child.<entry> (like #include prefix = $true)
    "child"         = $child
    # The discovery cache only sees this file, so list the dot-sourced maps to rebuild it when they change
    _cacheDependsOn = @("child/.build.map.ps1", "shared/.build.map.ps1")
}

# Merged into this map (like #include prefix = $false)
foreach ($key in $shared.Keys) {
    $map[$key] = $shared[$key]
}

$map
