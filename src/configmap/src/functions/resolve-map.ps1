# in order to make imports from the map file work globally, we have to call dot-source from top-level scope.
# hence this pattern:
# $map = Resolve-ConfigMap $map | ForEach-Object { $_ -is [string] ? (. $_) : $_ } | Assert-ConfigMap
function Resolve-ConfigMap {
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        # we want to allow passing objects or strings as map
        # somehow validateScript is throwing an error when $map is null
        # [ValidateScript({ $null -eq $_ -or $_ -is [string] -or $_ -is [System.Collections.IDictionary] })]
        $map,
        [Parameter(Mandatory = $false)]
        $fallback,
        [switch][bool]$lookUp = $true
    )

    if ($map -is [string] -or !$map) {
        $map = Resolve-ConfigMapFile $map $fallback
    }
    if (!$map) {
        throw "No map provided and fallback '$fallback' not found"
    }
    return $map
}


function Resolve-ConfigMapFile {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$mapFile,
        [Parameter(Mandatory = $false)]
        [string]$fallback
    )

    # Set default map file if null
    if (!$map) {
        if (!$fallback) {
            throw "map is null and defaultMapFile is not provided"
            return $null
        }
        $map = $fallback
    }

    # Load map from file if it's a string path
    $fullPath = [System.IO.Path]::IsPathRooted($map) ? $map : (Join-Path $PWD.Path $map)
    $file = Split-Path $fullPath -Leaf
    $dir = Split-Path $fullPath -Parent

    do {
        $fullPath = Join-Path $dir $file
        if (Test-Path $fullPath) {
            return $fullPath
        }
        $dir = Split-Path $dir -Parent
    } while ($lookUp -and $dir)

    throw "map file '$map' not found"
    return $null
}

function Assert-ConfigMap {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $map
    )
    # Validate that we have a loaded map
    if (!$map) {
        throw "failed to load map"
        return $null
    }

    if ($map -isnot [System.Collections.IDictionary]) {
        throw "map is not a dictionary"
    }

    return $map
}

function Add-BaseDir {
    <#
    .SYNOPSIS
        Recursively injects _baseDir property into map entries
    .DESCRIPTION
        Adds _baseDir to dictionary entries (directly).
        Wraps bare scriptblock leaf entries in @{ exec = scriptblock, _baseDir = ... } dictionaries
        so they can carry the _baseDir metadata needed for directory switching.
        Skips reserved keys like exec, set, get, description, etc.
    #>
    param(
        [System.Collections.IDictionary]$map,
        [string]$baseDir
    )
    
    if (!$map -or !$baseDir) {
        return $map
    }

    $reservedKeys = @("exec", "set", "get", "options", "list", "description", "#include")
    
    foreach ($key in @($map.Keys)) {
        $value = $map[$key]
        
        # Skip reserved keys
        if ($key -in $reservedKeys) {
            continue
        }
        
        # If value is a bare scriptblock (leaf entry), wrap it with _baseDir
        if ($value -is [scriptblock]) {
            $map[$key] = @{
                exec = $value
                _baseDir = $baseDir
            }
            continue
        }
        
        # If value is a dictionary, add _baseDir and recurse
        if ($value -is [System.Collections.IDictionary]) {
            $value._baseDir = $baseDir
            Add-BaseDir $value $baseDir | Out-Null
        }
    }
    
    return $map
}
