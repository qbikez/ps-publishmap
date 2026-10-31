#requires -version 7.0

$script:discoveryCacheMemory = @{}
$script:discoveryCacheVersion = 1

function Get-ConfigMapUserHome {
    if ($env:HOME) {
        return [System.IO.Path]::GetFullPath($env:HOME)
    }

    return [System.IO.Path]::GetFullPath([Environment]::GetFolderPath('UserProfile'))
}

function ConvertTo-ConfigMapDiscoveryCacheProjectName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile
    )

    $dir = [System.IO.Path]::GetFullPath((Split-Path -Parent $SourceFile)).TrimEnd('\', '/')
    $dir = $dir -replace ':', ''
    return ($dir -replace '[\\/]', '-')
}

function Get-ConfigMapDiscoveryCacheFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [ValidateSet('build', 'conf')]
        [string]$Language
    )

    $leaf = Split-Path -Leaf $SourceFile
    $name = if ($leaf -match '^\.(.+)\.map\.ps1$') {
        $Matches[1]
    }
    else {
        [System.IO.Path]::GetFileNameWithoutExtension($leaf)
    }

    $isCanonical = ($Language -eq 'build' -and $name -eq 'build') -or
    ($Language -eq 'conf' -and $name -eq 'configuration')
    if ($isCanonical) {
        return "discovery.$name.cache.json"
    }

    return "discovery.$name.$Language.cache.json"
}

function Get-ConfigMapDiscoveryCacheSettingOverrides {
    param([System.Collections.IDictionary]$Map)

    if (!$Map -or $Map._settings -isnot [System.Collections.IDictionary]) {
        return $null
    }

    $overrides = @{}
    foreach ($name in @('DiscoveryCache', 'DiscoveryCacheLocation')) {
        if ($Map._settings.Contains($name)) {
            $overrides[$name] = $Map._settings[$name]
        }
    }

    if ($overrides.Count -eq 0) {
        return $null
    }

    return $overrides
}

function Resolve-ConfigMapDiscoveryCacheLocation {
    param($Value)

    if ($null -eq $Value -or "$Value" -eq '') {
        $Value = Get-ConfigMapSetting -Name DiscoveryCacheLocation
    }

    $normalized = "$Value".Trim().ToLowerInvariant()
    if ($normalized -notin @('local', 'user')) {
        throw "DiscoveryCacheLocation must be 'local' or 'user'."
    }

    return $normalized
}

function Get-ConfigMapDiscoveryCachePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [ValidateSet('build', 'conf')]
        [string]$Language,
        [System.Collections.IDictionary]$Map,
        [string]$Location
    )

    $fullPath = [System.IO.Path]::GetFullPath($SourceFile)
    if (-not $Location) {
        $previous = Enter-ConfigMapSettingsScope -Settings (Get-ConfigMapDiscoveryCacheSettingOverrides -Map $Map)
        try {
            $Location = Resolve-ConfigMapDiscoveryCacheLocation
        }
        finally {
            Exit-ConfigMapSettingsScope -PreviousSettings $previous
        }
    }
    else {
        $Location = Resolve-ConfigMapDiscoveryCacheLocation -Value $Location
    }

    $fileName = Get-ConfigMapDiscoveryCacheFileName -SourceFile $fullPath -Language $Language
    $cacheDir = if ($Location -eq 'user') {
        Join-Path (Join-Path (Get-ConfigMapUserHome) '.configmap') (ConvertTo-ConfigMapDiscoveryCacheProjectName -SourceFile $fullPath)
    }
    else {
        Join-Path (Split-Path -Parent $fullPath) '.configmap'
    }

    return Join-Path $cacheDir $fileName
}

function Get-ConfigMapDiscoveryCacheCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [ValidateSet('build', 'conf')]
        [string]$Language,
        [ValidateSet('local', 'user')]
        [string]$Location
    )

    $fullPath = [System.IO.Path]::GetFullPath($SourceFile)
    return [pscustomobject]@{
        Location  = $Location
        Path      = Get-ConfigMapDiscoveryCachePath -SourceFile $fullPath -Language $Language -Location $Location
        MemoryKey = Get-ConfigMapDiscoveryMemoryKey -SourceFile $fullPath -Language $Language -Location $Location
    }
}

function Get-ConfigMapDiscoveryCacheCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [ValidateSet('build', 'conf')]
        [string]$Language
    )

    return @(
        Get-ConfigMapDiscoveryCacheCandidate -SourceFile $SourceFile -Language $Language -Location local
        Get-ConfigMapDiscoveryCacheCandidate -SourceFile $SourceFile -Language $Language -Location user
    )
}

function Get-ConfigMapDiscoveryCacheTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [ValidateSet('build', 'conf')]
        [string]$Language,
        [System.Collections.IDictionary]$Map
    )

    $previous = Enter-ConfigMapSettingsScope -Settings (Get-ConfigMapDiscoveryCacheSettingOverrides -Map $Map)
    try {
        $location = Resolve-ConfigMapDiscoveryCacheLocation
        return Get-ConfigMapDiscoveryCacheCandidate -SourceFile $SourceFile -Language $Language -Location $location
    }
    finally {
        Exit-ConfigMapSettingsScope -PreviousSettings $previous
    }
}

function Find-ConfigMapDiscoveryCache {
    <#
    .SYNOPSIS
        Finds a valid discovery cache by probing local and user files.
    .DESCRIPTION
        Does not read map settings. Validity uses only the cache payload and
        dependency file mtimes stored in that payload.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [ValidateSet('build', 'conf')]
        [string]$Language,
        [switch]$WriteMemory
    )

    $sourceFile = [System.IO.Path]::GetFullPath($SourceFile)
    $candidates = Get-ConfigMapDiscoveryCacheCandidates -SourceFile $sourceFile -Language $Language

    foreach ($candidate in $candidates) {
        $memoryCache = $script:discoveryCacheMemory[$candidate.MemoryKey]
        if (Test-ConfigMapDiscoveryCacheValid -Cache $memoryCache -SourceFile $sourceFile -Language $Language) {
            return [pscustomobject]@{
                Cache     = $memoryCache
                Candidate = $candidate
                Source    = 'memory'
            }
        }
    }

    foreach ($candidate in $candidates) {
        $diskCache = Read-ConfigMapDiscoveryCache -CachePath $candidate.Path
        if (Test-ConfigMapDiscoveryCacheValid -Cache $diskCache -SourceFile $sourceFile -Language $Language) {
            if ($WriteMemory) {
                $script:discoveryCacheMemory[$candidate.MemoryKey] = $diskCache
            }
            return [pscustomobject]@{
                Cache     = $diskCache
                Candidate = $candidate
                Source    = 'disk'
            }
        }
    }

    return $null
}

function Get-ConfigMapDiscoveryMemoryKey {
    param(
        [string]$SourceFile,
        [string]$Language,
        [string]$Location = 'local'
    )
    return "$([System.IO.Path]::GetFullPath($SourceFile))|$Language|$Location"
}

function Add-ConfigMapDependsOnDependencies {
    param(
        [System.Collections.IDictionary]$Node,
        [hashtable]$OperationContext,
        [System.Collections.IDictionary]$Map = $null
    )

    if (!$Node -or !$OperationContext) {
        return
    }
    if (-not $Node.Contains('_dependsOn')) {
        return
    }

    $raw = $Node['_dependsOn']
    if ($null -eq $raw) {
        return
    }

    $paths = if ($raw -is [System.Collections.IEnumerable] -and $raw -isnot [string]) {
        @($raw)
    }
    else {
        @($raw)
    }

    $baseDir = $null
    if ($Node._baseDir) {
        $baseDir = [string]$Node._baseDir
    }
    elseif ($Map -and $Map._baseDir) {
        $baseDir = [string]$Map._baseDir
    }
    elseif ($Map -and $Map._sourceFile) {
        $baseDir = Split-Path -Parent $Map._sourceFile
    }
    elseif ($Node._sourceFile) {
        $baseDir = Split-Path -Parent $Node._sourceFile
    }

    foreach ($item in $paths) {
        if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        $path = $item

        if ([System.IO.Path]::IsPathRooted($path)) {
            $fullPath = [System.IO.Path]::GetFullPath($path)
        }
        else {
            $resolved = if ($baseDir) { Join-Path $baseDir $path } else { $path }
            $fullPath = [System.IO.Path]::GetFullPath($resolved)
        }

        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $OperationContext.Dependencies[$fullPath] = (Get-Item -LiteralPath $fullPath).LastWriteTimeUtc.Ticks
        }
        else {
            $OperationContext.Dependencies[$fullPath] = $null
        }
    }
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

    try {
        $dir = Split-Path -Parent $CachePath
        if (!(Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }

        $json = $Cache | ConvertTo-Json -Depth 8
        Set-Content -LiteralPath $CachePath -Value $json -Encoding utf8 -ErrorAction Stop
    }
    catch {
    }
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

    $pair = Get-MapEntryListPair -map $Map -language $Language -OperationContext $operationContext

    return @{
        version      = $script:discoveryCacheVersion
        rootMap      = $sourceFile
        language     = $Language
        dependencies = @(ConvertTo-ConfigMapDiscoveryDependencyList $operationContext.Dependencies)
        entries      = @{
            hierarchical = @(ConvertTo-ConfigMapDiscoveryEntryDescriptors $pair.hierarchical $Language)
            flatten      = @(ConvertTo-ConfigMapDiscoveryEntryDescriptors $pair.flatten $Language)
        }
    }
}

function Test-ConfigMapDiscoveryCacheEnabled {
    param([System.Collections.IDictionary]$Map)

    $previous = Enter-ConfigMapSettingsScope -Settings (Get-ConfigMapDiscoveryCacheSettingOverrides -Map $Map)
    try {
        return Test-ConfigMapFeatureEnabled -Name DiscoveryCache
    }
    finally {
        Exit-ConfigMapSettingsScope -PreviousSettings $previous
    }
}

function Get-ConfigMapDiscoveryCache {
    <#
    .SYNOPSIS
        Returns a fresh or rebuilt discovery cache for a file-backed map.
    .DESCRIPTION
        Skips disk cache when the map has no _sourceFile (in-memory maps).
        Probes local and user cache files without reading map settings.
        Disabled when DiscoveryCache is opted out via _settings or QCONF_DiscoveryCache.
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

    if (-not (Test-ConfigMapDiscoveryCacheEnabled -Map $Map)) {
        return $null
    }

    $sourceFile = [System.IO.Path]::GetFullPath($Map._sourceFile)
    $found = Find-ConfigMapDiscoveryCache -SourceFile $sourceFile -Language $Language -WriteMemory
    if ($found) {
        return $found.Cache
    }

    $target = Get-ConfigMapDiscoveryCacheTarget -SourceFile $sourceFile -Language $Language -Map $Map
    $built = Build-ConfigMapDiscoveryCache -Map $Map -Language $Language
    Write-ConfigMapDiscoveryCache -CachePath $target.Path -Cache $built
    $script:discoveryCacheMemory[$target.MemoryKey] = $built
    return $built
}

function Clear-ConfigMapDiscoveryCacheMemory {
    param([string]$MemoryKey)

    if ($MemoryKey) {
        $script:discoveryCacheMemory.Remove($MemoryKey) | Out-Null
        return
    }

    $script:discoveryCacheMemory = @{}
}

function New-ConfigMapDiscoveryCacheInfo {
    param(
        [string]$Action,
        [bool]$Enabled,
        [string]$Path,
        [bool]$Exists,
        [bool]$Valid,
        [string]$Source,
        [string]$RootMap,
        [string]$Language,
        [string]$Location,
        $Cache
    )

    $entryCount = 0
    $version = $null
    $dependencies = @()
    if ($Cache) {
        $version = $Cache.version
        if ($Cache.entries -and $null -ne $Cache.entries.hierarchical) {
            $entryCount = @($Cache.entries.hierarchical).Count
        }
        if ($Cache.dependencies) {
            $dependencies = @($Cache.dependencies)
        }
        if (-not $RootMap -and $Cache.rootMap) {
            $RootMap = [string]$Cache.rootMap
        }
    }

    return [pscustomobject]@{
        Action       = $Action
        Enabled      = [bool]$Enabled
        Location     = $Location
        Path         = $Path
        Exists       = [bool]$Exists
        Valid        = [bool]$Valid
        Source       = $Source
        Version      = $version
        RootMap      = $RootMap
        Language     = $Language
        EntryCount   = $entryCount
        Dependencies = $dependencies
    }
}

function Get-ConfigMapDiscoveryCacheInfo {
    <#
    .SYNOPSIS
        Inspects discovery cache state for a map without rebuilding it.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        [ValidateSet('build', 'conf')]
        [string]$Language,
        [string]$Action = 'status'
    )

    $enabled = Test-ConfigMapDiscoveryCacheEnabled -Map $Map
    if (!$Map._sourceFile) {
        $previous = Enter-ConfigMapSettingsScope -Settings (Get-ConfigMapDiscoveryCacheSettingOverrides -Map $Map)
        try {
            $location = Resolve-ConfigMapDiscoveryCacheLocation
        }
        finally {
            Exit-ConfigMapSettingsScope -PreviousSettings $previous
        }
        return New-ConfigMapDiscoveryCacheInfo -Action $Action -Enabled $enabled -Location $location -Path $null -Exists $false -Valid $false -Source 'none' -RootMap $null -Language $Language
    }

    $sourceFile = [System.IO.Path]::GetFullPath($Map._sourceFile)
    $found = Find-ConfigMapDiscoveryCache -SourceFile $sourceFile -Language $Language
    if ($found) {
        $exists = Test-Path -LiteralPath $found.Candidate.Path -PathType Leaf
        return New-ConfigMapDiscoveryCacheInfo -Action $Action -Enabled $enabled -Location $found.Candidate.Location -Path $found.Candidate.Path -Exists $exists -Valid $true -Source $found.Source -RootMap $sourceFile -Language $Language -Cache $found.Cache
    }

    foreach ($candidate in (Get-ConfigMapDiscoveryCacheCandidates -SourceFile $sourceFile -Language $Language)) {
        $stale = Read-ConfigMapDiscoveryCache -CachePath $candidate.Path
        if ($stale) {
            $exists = Test-Path -LiteralPath $candidate.Path -PathType Leaf
            return New-ConfigMapDiscoveryCacheInfo -Action $Action -Enabled $enabled -Location $candidate.Location -Path $candidate.Path -Exists $exists -Valid $false -Source 'none' -RootMap $sourceFile -Language $Language -Cache $stale
        }
    }

    $target = Get-ConfigMapDiscoveryCacheTarget -SourceFile $sourceFile -Language $Language -Map $Map
    return New-ConfigMapDiscoveryCacheInfo -Action $Action -Enabled $enabled -Location $target.Location -Path $target.Path -Exists $false -Valid $false -Source 'none' -RootMap $sourceFile -Language $Language
}

function Clear-ConfigMapDiscoveryCache {
    <#
    .SYNOPSIS
        Deletes the discovery cache file and memory entry for a map.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        [ValidateSet('build', 'conf')]
        [string]$Language
    )

    if ($Map._sourceFile) {
        $sourceFile = [System.IO.Path]::GetFullPath($Map._sourceFile)
        foreach ($candidate in (Get-ConfigMapDiscoveryCacheCandidates -SourceFile $sourceFile -Language $Language)) {
            Clear-ConfigMapDiscoveryCacheMemory -MemoryKey $candidate.MemoryKey
            if (Test-Path -LiteralPath $candidate.Path -PathType Leaf) {
                Remove-Item -LiteralPath $candidate.Path -Force
            }
        }
    }

    return Get-ConfigMapDiscoveryCacheInfo -Map $Map -Language $Language -Action 'clear'
}

function Rebuild-ConfigMapDiscoveryCache {
    <#
    .SYNOPSIS
        Clears and rebuilds the discovery cache for a file-backed map.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        [ValidateSet('build', 'conf')]
        [string]$Language
    )

    if (-not (Test-ConfigMapDiscoveryCacheEnabled -Map $Map)) {
        throw "Discovery cache is disabled. Enable it with _settings.DiscoveryCache or unset QCONF_DiscoveryCache."
    }

    if (!$Map._sourceFile) {
        throw "Cannot rebuild discovery cache for an in-memory map."
    }

    $null = Clear-ConfigMapDiscoveryCache -Map $Map -Language $Language

    $sourceFile = [System.IO.Path]::GetFullPath($Map._sourceFile)
    $target = Get-ConfigMapDiscoveryCacheTarget -SourceFile $sourceFile -Language $Language -Map $Map
    $built = Build-ConfigMapDiscoveryCache -Map $Map -Language $Language
    Write-ConfigMapDiscoveryCache -CachePath $target.Path -Cache $built
    $script:discoveryCacheMemory[$target.MemoryKey] = $built

    return Get-ConfigMapDiscoveryCacheInfo -Map $Map -Language $Language -Action 'rebuild'
}

function Invoke-QBuildCacheCommand {
    <#
    .SYNOPSIS
        Runs a qbuild !cache subcommand against the user's map.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Context,
        [ValidateSet('status', 'clear', 'rebuild')]
        [string]$Action = 'status',
        [switch]$Porcelain
    )

    if (@($Context.RemainingArguments | Where-Object { $_ }).Count -gt 0) {
        throw "!cache takes no arguments. Use !cache.status, !cache.clear, or !cache.rebuild."
    }

    if (!$Context.UserMap) {
        throw "No build map file found. Run 'qbuild !init' to create one, or provide -map."
    }

    $info = switch ($Action) {
        'status' { Get-ConfigMapDiscoveryCacheInfo -Map $Context.UserMap -Language build -Action 'status' }
        'clear' { Clear-ConfigMapDiscoveryCache -Map $Context.UserMap -Language build }
        'rebuild' { Rebuild-ConfigMapDiscoveryCache -Map $Context.UserMap -Language build }
    }

    if ($Porcelain) {
        return $info
    }

    Write-QBuildCacheInfo -Info $info
}

function Write-QBuildCacheInfo {
    param(
        [Parameter(Mandatory = $true)]
        $Info
    )

    $title = switch ($Info.Action) {
        'clear' { 'Discovery cache cleared' }
        'rebuild' { 'Discovery cache rebuilt' }
        default { 'Discovery cache' }
    }

    $state, $stateColor = if ($Info.Valid) { "valid ($($Info.Source))", 'Green' }
    elseif ($Info.Exists) { 'stale', 'Yellow' }
    else { 'missing', 'DarkGray' }

    $rows = [ordered]@{
        Enabled    = if ($Info.Enabled) { 'yes' } else { 'no' }
        Location   = $Info.Location
        Path       = $Info.Path
        'Root map' = $Info.RootMap
    }
    if ($Info.Exists) {
        $rows['Version'] = $Info.Version
        $rows['Entries'] = $Info.EntryCount
        $rows['Dependencies'] = @($Info.Dependencies).Count
    }

    Write-Host ""
    Write-Host $title -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    $('State'.PadRight(14))" -NoNewline
    Write-Host $state -ForegroundColor $stateColor
    foreach ($row in $rows.GetEnumerator()) {
        if ($null -eq $row.Value -or $row.Value -eq '') {
            continue
        }
        Write-Host "    $(([string]$row.Key).PadRight(14))" -NoNewline
        Write-Host $row.Value -ForegroundColor White
    }
}
