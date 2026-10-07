#requires -version 7.0

$script:discoveryCacheMemory = @{}
$script:discoveryCacheVersion = 1

function Get-ConfigMapDiscoveryCachePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [ValidateSet('build', 'conf')]
        [string]$Language
    )

    $fullPath = [System.IO.Path]::GetFullPath($SourceFile)
    $dir = Split-Path -Parent $fullPath
    $leaf = Split-Path -Leaf $fullPath
    $name = if ($leaf -match '^\.(.+)\.map\.ps1$') {
        $Matches[1]
    }
    else {
        [System.IO.Path]::GetFileNameWithoutExtension($leaf)
    }

    return Join-Path (Join-Path $dir '.configmap') "discovery.$name.cache.json"
}

function Get-ConfigMapDiscoveryMemoryKey {
    param(
        [string]$SourceFile,
        [string]$Language
    )
    return "$([System.IO.Path]::GetFullPath($SourceFile))|$Language"
}

function ConvertTo-ConfigMapDiscoveryDependencyList {
    param([hashtable]$Dependencies)

    $list = @()
    foreach ($path in ($Dependencies.Keys | Sort-Object)) {
        $list += @{
            path  = $path
            ticks = $Dependencies[$path]
        }
    }
    return $list
}

function Get-EntryParameterMeta {
    <#
    .SYNOPSIS
        Extracts static parameter metadata from a scriptblock AST without resolving @sibling ValidateSet.
    #>
    param([scriptblock]$Func)

    $result = @()
    if (!$Func -or !$Func.Ast.ParamBlock -or !$Func.Ast.ParamBlock.Parameters) {
        return $result
    }

    $exclude = @('$_context', '$_self')
    foreach ($ast in $Func.Ast.ParamBlock.Parameters) {
        $name = $ast.Name.ToString().Trim('`$')
        if ("`$$name" -in $exclude -or $name -in @('_context', '_self')) {
            continue
        }

        $paramType = $ast.StaticType
        $isSwitch = $false
        $validateSet = $null
        $hasValidateSet = $false
        $staticValues = @()

        foreach ($attr in $ast.Attributes) {
            if ($attr -is [System.Management.Automation.Language.TypeConstraintAst]) {
                if ($attr.TypeName.ToString() -eq 'switch') {
                    $paramType = [switch]
                    $isSwitch = $true
                }
            }
            elseif ($attr -is [System.Management.Automation.Language.AttributeAst]) {
                $typeName = $attr.TypeName.ToString() -replace '^.*\.', ''
                if ($typeName -eq 'ValidateSet') {
                    $hasValidateSet = $true
                    foreach ($arg in $attr.PositionalArguments) {
                        if ($arg -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                            $staticValues += $arg.Value
                        }
                    }
                }
            }
        }

        if ($paramType -eq [switch]) {
            $isSwitch = $true
        }

        if ($hasValidateSet) {
            if ($staticValues.Count -eq 1 -and $staticValues[0] -match '^@') {
                $validateSet = $null
            }
            elseif ($staticValues.Count -gt 0) {
                $validateSet = @($staticValues)
            }
        }

        $typeName = if ($isSwitch) {
            'switch'
        }
        elseif ($paramType -eq [string]) {
            'string'
        }
        else {
            $paramType.Name
        }

        $result += @{
            name        = $name
            type        = $typeName
            isSwitch    = [bool]$isSwitch
            validateSet = $validateSet
        }
    }

    return $result
}

function New-ConfigMapDiscoveryEntryDescriptor {
    param(
        [string]$Key,
        $Entry,
        [ValidateSet('build', 'conf')]
        [string]$Language
    )

    $reservedKeys = (Get-MapLanguage $Language).reservedKeys
    $isParent = Test-IsParentEntry $Entry -ReservedKeys $reservedKeys
    $description = ''
    if ($Entry -is [System.Collections.IDictionary] -and $Entry.description) {
        $description = [string]$Entry.description
    }

    $parameters = @()
    if (-not $isParent -and -not (Test-BuildAllEntry $Entry)) {
        try {
            $command = Get-EntryCommand $Entry 'exec'
            if ($command -is [scriptblock]) {
                $parameters = @(Get-EntryParameterMeta $command)
            }
        }
        catch {
            $parameters = @()
        }
    }

    return @{
        key         = $Key
        isParent    = [bool]$isParent
        description = $description
        parameters  = $parameters
    }
}

function ConvertTo-ConfigMapDiscoveryEntryDescriptors {
    param(
        [System.Collections.IDictionary]$EntryList,
        [ValidateSet('build', 'conf')]
        [string]$Language
    )

    $descriptors = @()
    foreach ($kvp in $EntryList.GetEnumerator()) {
        $descriptors += New-ConfigMapDiscoveryEntryDescriptor -Key $kvp.Key -Entry $kvp.Value -Language $Language
    }
    return $descriptors
}

function Test-ConfigMapDiscoveryCacheValid {
    param(
        $Cache,
        [string]$SourceFile,
        [ValidateSet('build', 'conf')]
        [string]$Language
    )

    if (!$Cache) { return $false }
    if ($Cache.version -ne $script:discoveryCacheVersion) { return $false }

    $rootMap = [System.IO.Path]::GetFullPath($SourceFile)
    if ("$($Cache.rootMap)" -ne $rootMap) { return $false }
    if ("$($Cache.language)" -ne $Language) { return $false }
    if (!$Cache.dependencies) { return $false }

    foreach ($dep in @($Cache.dependencies)) {
        $path = [string]$dep.path
        if ([string]::IsNullOrEmpty($path)) { return $false }

        $exists = Test-Path -LiteralPath $path -PathType Leaf
        $storedTicks = $dep.ticks

        if ($null -eq $storedTicks) {
            if ($exists) { return $false }
            continue
        }

        if (-not $exists) { return $false }

        $currentTicks = (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
        if ([int64]$currentTicks -ne [int64]$storedTicks) { return $false }
    }

    return $true
}

function Read-ConfigMapDiscoveryCache {
    param([string]$CachePath)

    if (!(Test-Path -LiteralPath $CachePath -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $CachePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Write-ConfigMapDiscoveryCache {
    param(
        [string]$CachePath,
        $Cache
    )

    $dir = Split-Path -Parent $CachePath
    if (!(Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $Cache | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $CachePath -Value $json -Encoding utf8
}

function Build-ConfigMapDiscoveryCache {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        [ValidateSet('build', 'conf')]
        [string]$Language
    )

    $sourceFile = [System.IO.Path]::GetFullPath($Map._sourceFile)
    $operationContext = New-ConfigMapOperationContext
    $operationContext.Dependencies[$sourceFile] = (Get-Item -LiteralPath $sourceFile).LastWriteTimeUtc.Ticks

    $hierarchical = Get-MapEntryList -map $Map -language $Language -OperationContext $operationContext
    $flatten = Get-MapEntryList -map $Map -language $Language -flatten -OperationContext $operationContext

    return @{
        version      = $script:discoveryCacheVersion
        rootMap      = $sourceFile
        language     = $Language
        dependencies = @(ConvertTo-ConfigMapDiscoveryDependencyList $operationContext.Dependencies)
        entries      = @{
            hierarchical = @(ConvertTo-ConfigMapDiscoveryEntryDescriptors $hierarchical $Language)
            flatten      = @(ConvertTo-ConfigMapDiscoveryEntryDescriptors $flatten $Language)
        }
    }
}

function Get-ConfigMapDiscoveryCache {
    <#
    .SYNOPSIS
        Returns a fresh or rebuilt discovery cache for a file-backed map.
    .DESCRIPTION
        Skips disk cache when the map has no _sourceFile (in-memory maps).
        Uses a process memory layer keyed by source file and language.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        [ValidateSet('build', 'conf')]
        [string]$Language
    )

    if (!$Map._sourceFile) {
        return $null
    }

    $sourceFile = [System.IO.Path]::GetFullPath($Map._sourceFile)
    $memoryKey = Get-ConfigMapDiscoveryMemoryKey -SourceFile $sourceFile -Language $Language

    $memoryCache = $script:discoveryCacheMemory[$memoryKey]
    if (Test-ConfigMapDiscoveryCacheValid -Cache $memoryCache -SourceFile $sourceFile -Language $Language) {
        return $memoryCache
    }

    $cachePath = Get-ConfigMapDiscoveryCachePath -SourceFile $sourceFile -Language $Language
    $diskCache = Read-ConfigMapDiscoveryCache -CachePath $cachePath
    if (Test-ConfigMapDiscoveryCacheValid -Cache $diskCache -SourceFile $sourceFile -Language $Language) {
        $script:discoveryCacheMemory[$memoryKey] = $diskCache
        return $diskCache
    }

    $built = Build-ConfigMapDiscoveryCache -Map $Map -Language $Language
    Write-ConfigMapDiscoveryCache -CachePath $cachePath -Cache $built
    $script:discoveryCacheMemory[$memoryKey] = $built
    return $built
}

function Clear-ConfigMapDiscoveryCacheMemory {
    $script:discoveryCacheMemory = @{}
}
