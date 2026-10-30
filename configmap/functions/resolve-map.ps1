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
    
    foreach ($key in @($map.Keys)) {
        $value = $map[$key]
        
        # Skip reserved keys
        if ($key -in $reservedKeys) {
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

function Import-IncludedConfigMap {
    param(
        [string]$DirectoryName,
        [string]$BaseDir,
        [hashtable]$Cache,
        [hashtable]$Loading
    )

    if ([string]::IsNullOrEmpty($BaseDir)) {
        $BaseDir = (Get-Location).Path
    }

    $includePath = Join-Path $BaseDir $DirectoryName
    if (!(Test-Path $includePath -PathType Container)) {
        return $null
    }

    $mapFile = Join-Path $includePath '.build.map.ps1'
    if (!(Test-Path $mapFile -PathType Leaf)) {
        return $null
    }

    $cacheKey = [System.IO.Path]::GetFullPath($mapFile)
    if ($Cache.ContainsKey($cacheKey)) {
        return $Cache[$cacheKey]
    }
    if ($Loading.ContainsKey($cacheKey)) {
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
