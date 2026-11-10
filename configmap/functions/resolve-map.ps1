function Resolve-ConfigMap {
    [OutputType([PSCustomObject])]
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

    if ($map -is [System.Collections.IDictionary]) {
        return [PSCustomObject]@{
            source     = "object"
            sourceFile = $null
            map        = $map
        }
    }

    $sourceFile = Resolve-ConfigMapFile -MapFile $map -Fallback $fallback -LookUp:$lookUp
    if (!$sourceFile) {
        throw "No map provided and fallback '$fallback' not found"
    }
    return [PSCustomObject]@{
        source     = "file"
        sourceFile = $sourceFile
        map        = $null
    }
}


function Resolve-ConfigMapFile {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$mapFile,
        [Parameter(Mandatory = $false)]
        [string]$fallback,
        [switch][bool]$lookUp = $true
    )

    # Set default map file if null
    if (!$mapFile) {
        if (!$fallback) {
            throw "map is null and defaultMapFile is not provided"
        }
        $mapFile = $fallback
    }

    # Load map from file if it's a string path
    $fullPath = [System.IO.Path]::IsPathRooted($mapFile) ? $mapFile : (Join-Path $PWD.Path $mapFile)
    $file = Split-Path $fullPath -Leaf
    $dir = Split-Path $fullPath -Parent

    $supportsChildNamedParentMap = $file -match '^\.[^.]+\.map\.ps1$'

    do {
        $fullPath = Join-Path $dir $file
        if (Test-Path $fullPath) {
            return $fullPath
        }

        $parentDir = Split-Path $dir -Parent
        if ($lookUp -and $supportsChildNamedParentMap -and $parentDir) {
            $childDirName = Split-Path $dir -Leaf
            if ($childDirName) {
                $childNamedMap = Join-Path $parentDir ".$childDirName.map.ps1"
                if (Test-Path $childNamedMap) {
                    return $childNamedMap
                }
            }
        }

        $dir = $parentDir
    } while ($lookUp -and $dir)

    throw "map file '$mapFile' not found"
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
        If baseDir is a file path, automatically extracts the parent directory.
    #>
    param(
        [Parameter(ValueFromPipeline = $true)]
        [System.Collections.IDictionary]$map,
        [string]$baseDir
    )

    if (!$map -or !$baseDir) {
        return $map
    }

    # If baseDir is a file, get its parent directory
    if ((Test-Path $baseDir -PathType Leaf) -or [System.IO.Path]::GetExtension($baseDir)) {
        $baseDir = Split-Path $baseDir -Parent
    }

    $map._baseDir = $baseDir

    $reservedKeys = (Get-MapLanguage build).reservedKeys
    $siblingKeys = @(Get-EntryValueSourceKey $map) + @(Get-EntryHandlerKey $map)

    foreach ($key in @($map.Keys)) {
        $value = $map[$key]

        # Skip reserved keys, ValidateSet('@key') value sources and handlers such as a steps `check`, which are not entries
        if ($key -in $reservedKeys -or $key -in $siblingKeys) {
            continue
        }
        
        # If value is a bare scriptblock (leaf entry), wrap it with _baseDir
        if ($value -is [scriptblock]) {
            $map[$key] = @{
                exec     = $value
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

function Test-IncludeIsMapFile {
    # An #include key names either a directory holding .build.map.ps1 or a map file itself
    param([string]$Include)

    return $Include.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-IncludedMapFile {
    [OutputType([string])]
    param(
        [string]$Include,
        [string]$BaseDir
    )

    if ([string]::IsNullOrEmpty($BaseDir)) {
        $BaseDir = (Get-Location).Path
    }

    $path = Join-Path $BaseDir $Include
    if (!(Test-IncludeIsMapFile $Include)) {
        $path = Join-Path $path '.build.map.ps1'
    }

    return [System.IO.Path]::GetFullPath($path)
}

function Get-IncludePrefix {
    <#
    .SYNOPSIS
        Returns the entry prefix of a prefixed #include.
    .DESCRIPTION
        A directory include is prefixed with the directory name. A map file include is prefixed
        with the file name without its map suffix (tools/lint.build.map.ps1 and .lint.map.ps1 -> lint);
        a file named .build.map.ps1 takes its directory name.
    #>
    [OutputType([string])]
    param([string]$Include)

    if (!(Test-IncludeIsMapFile $Include)) {
        return $Include
    }

    $name = (Split-Path $Include -Leaf) -replace '\.ps1$', '' -replace '\.map$', '' -replace '\.(build|configuration)$', '' -replace '^\.', ''
    if ($name) {
        return $name
    }

    $parent = Split-Path $Include -Parent
    return $parent ? (Split-Path $parent -Leaf) : $Include
}

function Import-IncludedConfigMap {
    param(
        [string]$Include,
        [string]$BaseDir,
        [hashtable]$Cache,
        [hashtable]$Loading
    )

    $mapFile = Resolve-IncludedMapFile -Include $Include -BaseDir $BaseDir
    $cacheKey = $mapFile
    # Checked before Test-Path: map walks hit the same include once per entry, and provider calls dominate their cost.
    if ($Cache.ContainsKey($cacheKey)) {
        return $Cache[$cacheKey]
    }
    if ($Loading.ContainsKey($cacheKey)) {
        return $null
    }

    if (!(Test-Path -LiteralPath $mapFile -PathType Leaf)) {
        return $null
    }

    $Loading[$cacheKey] = $true
    try {
        $includedMap = . $mapFile | Assert-ConfigMap
        $includedMap = Add-BaseDir $includedMap $mapFile
        $Cache[$cacheKey] = $includedMap
        return $includedMap
    }
    finally {
        $Loading.Remove($cacheKey)
    }
}

# Handlers use load hooks to enrich entries they understand (extra child entries, lazy options)
# without core knowing their entry types. Hooks run on maps loaded from a file.
$script:ConfigMapLoadHooks = [System.Collections.Generic.Dictionary[string, scriptblock]]::new(
    [StringComparer]::OrdinalIgnoreCase
)

function Register-ConfigMapLoadHook {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        # param([System.Collections.IDictionary]$Map): mutates the freshly loaded map
        [Parameter(Mandatory = $true)]
        [scriptblock]$Hook
    )

    $script:ConfigMapLoadHooks[$Name] = $Hook
}

function Invoke-ConfigMapLoadHook {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map
    )

    foreach ($hook in $script:ConfigMapLoadHooks.Values) {
        $null = & $hook $Map
    }
}

# Dot-source this scriptblock. A function would drop map-file imports when it returned.
# . $ImportConfigMap -Map $map -Fallback './.build.map.ps1'
$script:ImportConfigMap = {
    [CmdletBinding()]
    param(
        $Map,
        $Fallback,
        [switch][bool]$LookUp = $true
    )

    $importConfigMapResult = $null
    try {
        $importConfigMapResolved = Resolve-ConfigMap -map $Map -fallback $Fallback -lookUp:$LookUp
        if ($importConfigMapResolved.source -eq 'file') {
            $importConfigMapSourceFile = $importConfigMapResolved.sourceFile
            $importConfigMapResult = . $importConfigMapSourceFile | Add-BaseDir -baseDir $importConfigMapSourceFile
            Invoke-ConfigMapLoadHook -Map $importConfigMapResult
            $importConfigMapResult._sourceFile = [System.IO.Path]::GetFullPath($importConfigMapSourceFile)
        }
        else {
            $importConfigMapResult = $importConfigMapResolved.map
        }
    }
    finally {
        Remove-Variable importConfigMapResolved, importConfigMapSourceFile, Fallback -ErrorAction SilentlyContinue
    }

    $importConfigMapResult
    Remove-Variable importConfigMapResult -ErrorAction SilentlyContinue
}

function Import-ConfigMap {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Map,
        $Fallback,
        [switch][bool]$LookUp = $true
    )

    . $script:ImportConfigMap @PSBoundParameters
}
