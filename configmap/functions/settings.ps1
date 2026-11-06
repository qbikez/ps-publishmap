# Current settings for map scripts and plugin hooks, which read them through Get-ConfigMapSetting.
# Only Invoke-WithRunContext changes it, for the duration of a script; module code takes settings
# from a run context instead.
$script:ConfigMapSettings = $null
# Defaults plus QCONF_* environment variables, captured at import or by Update-ConfigMapSettings.
# Entry settings are resolved from this base and the map, never from the caller's settings.
$script:ConfigMapBaseSettings = $null

function New-ConfigMapSettings {
    param(
        $BaseSettings,
        [System.Collections.IDictionary]$Overrides = @{}
    )

    $settings = @{
        Debug                  = $false
        Concurrently           = $false
        TmuxAutoWindow         = $false
        DiscoveryCache         = $true
        DiscoveryCacheLocation = 'local'
        Process                = $script:ConfigMapDefaultProcessName
        ForceCheck             = $false
        UseWorkDir             = $false
    }

    foreach ($propertyName in @($settings.Keys)) {
        $envPath = "env:QCONF_$propertyName"
        if (Test-Path -Path $envPath) {
            $settings[$propertyName] = (Get-Item -Path $envPath).Value
        }
    }

    if ($BaseSettings) {
        foreach ($propertyName in @($settings.Keys)) {
            $settings[$propertyName] = $BaseSettings.PSObject.Properties[$propertyName].Value
        }
    }

    foreach ($override in $Overrides.GetEnumerator()) {
        if (-not $settings.ContainsKey($override.Key)) {
            throw "Unknown ConfigMap setting '$($override.Key)'."
        }

        $settings[$override.Key] = $override.Value
    }

    $normalizedLocation = "$($settings.DiscoveryCacheLocation)".Trim().ToLowerInvariant()
    if ($normalizedLocation -notin @('local', 'user')) {
        throw "DiscoveryCacheLocation must be 'local' or 'user'."
    }
    $settings.DiscoveryCacheLocation = $normalizedLocation
    $settings.Process = Get-ConfigMapProcessCanonicalName -ProcessName "$($settings.Process)"

    $settingsObject = [pscustomobject]$settings
    $settingsObject.PSObject.TypeNames.Insert(0, 'ConfigMap.Settings')

    return $settingsObject
}

function Update-ConfigMapSettings {
    $script:ConfigMapBaseSettings = New-ConfigMapSettings
    $script:ConfigMapSettings = $script:ConfigMapBaseSettings

    return $script:ConfigMapSettings
}

function New-ConfigMapOperationContext {
    return @{
        IncludeCache    = @{}
        LoadingIncludes = @{}
        Dependencies    = @{}
    }
}

function Find-ConfigMapAncestorSettings {
    param(
        [System.Collections.IDictionary]$Node,
        [string[]]$Segments,
        [switch]$IncludeTarget,
        [System.Collections.Generic.HashSet[string]]$Visited,
        [hashtable]$Cache,
        [hashtable]$Loading
    )

    $notFound = [pscustomobject]@{ Found = $false; Settings = $null }
    if ($null -eq $Segments -or $Segments.Count -eq 0 -or $null -eq $Node) {
        return $notFound
    }

    $segment = $Segments[0]
    $rest = if ($Segments.Count -gt 1) { $Segments[1..($Segments.Count - 1)] } else { @() }
    $isLast = $rest.Count -eq 0
    $visitKey = '{0}|{1}' -f [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Node), $segment
    if (-not $Visited.Add($visitKey)) {
        return $notFound
    }

    $baseDir = $Node._baseDir
    $list = $Node
    if ($Node.list) {
        $list = $Node.list
    }
    if ($list -isnot [System.Collections.IDictionary]) {
        return $notFound
    }

    if ($list.Contains($segment)) {
        $settings = [System.Collections.Generic.List[object]]::new()
        $child = $list[$segment]
        $apply = (-not $isLast) -or $IncludeTarget
        if ($apply -and $child -is [System.Collections.IDictionary] -and $child._settings) {
            $settings.Add($child._settings)
        }
        if (-not $isLast -and $child -is [System.Collections.IDictionary]) {
            $inner = Find-ConfigMapAncestorSettings -Node $child -Segments $rest -IncludeTarget:$IncludeTarget -Visited $Visited -Cache $Cache -Loading $Loading
            if ($inner.Found) {
                foreach ($item in $inner.Settings) {
                    $settings.Add($item)
                }
            }
        }
        return [pscustomobject]@{ Found = $true; Settings = $settings }
    }

    $includes = $null
    if ($list.Contains('#include')) {
        $includes = $list['#include']
    }
    if ($includes -isnot [System.Collections.IDictionary]) {
        return $notFound
    }

    foreach ($inc in @($includes.GetEnumerator())) {
        $usePrefix = $inc.Value -is [System.Collections.IDictionary] -and $inc.Value.prefix -eq $true
        if (-not $usePrefix -or (Get-IncludePrefix "$($inc.Key)") -ne $segment) {
            continue
        }

        $included = Import-IncludedConfigMap -Include "$($inc.Key)" -BaseDir $baseDir -Cache $Cache -Loading $Loading
        if (-not $included) {
            continue
        }

        if ($isLast) {
            $settings = [System.Collections.Generic.List[object]]::new()
            if ($IncludeTarget -and $included._settings) {
                $settings.Add($included._settings)
            }
            return [pscustomobject]@{ Found = $true; Settings = $settings }
        }

        $inner = Find-ConfigMapAncestorSettings -Node $included -Segments $rest -IncludeTarget:$IncludeTarget -Visited $Visited -Cache $Cache -Loading $Loading
        if (-not $inner.Found) {
            continue
        }

        $settings = [System.Collections.Generic.List[object]]::new()
        if ($included._settings) {
            $settings.Add($included._settings)
        }
        foreach ($item in $inner.Settings) {
            $settings.Add($item)
        }
        return [pscustomobject]@{ Found = $true; Settings = $settings }
    }

    foreach ($inc in @($includes.GetEnumerator())) {
        $usePrefix = $inc.Value -is [System.Collections.IDictionary] -and $inc.Value.prefix -eq $true
        if ($usePrefix) {
            continue
        }

        $included = Import-IncludedConfigMap -Include "$($inc.Key)" -BaseDir $baseDir -Cache $Cache -Loading $Loading
        if (-not $included) {
            continue
        }

        $inner = Find-ConfigMapAncestorSettings -Node $included -Segments $Segments -IncludeTarget:$IncludeTarget -Visited $Visited -Cache $Cache -Loading $Loading
        if (-not $inner.Found) {
            continue
        }

        $settings = [System.Collections.Generic.List[object]]::new()
        if ($included._settings) {
            $settings.Add($included._settings)
        }
        foreach ($item in $inner.Settings) {
            $settings.Add($item)
        }
        return [pscustomobject]@{ Found = $true; Settings = $settings }
    }

    return $notFound
}

function Resolve-ConfigMapEntrySettings {
    <#
    .SYNOPSIS
        Effective settings for an entry: the base, then the map's _settings, then each ancestor's,
        then the entry's own. Reads no module state.
    #>
    param(
        [Parameter(Mandatory)]
        $BaseSettings,
        [System.Collections.IDictionary]$Map,
        [string]$EntryKey,
        $Entry,
        [hashtable]$OperationContext
    )

    $layers = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Map -and $Map._settings) {
        $layers.Add($Map._settings)
    }
    if ($null -ne $Map -and -not [string]::IsNullOrEmpty($EntryKey)) {
        $visited = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $includeCache = if ($OperationContext) { $OperationContext.IncludeCache } else { @{} }
        $loadingIncludes = if ($OperationContext) { $OperationContext.LoadingIncludes } else { @{} }
        $found = Find-ConfigMapAncestorSettings -Node $Map -Segments @($EntryKey -split '\.') -Visited $visited -Cache $includeCache -Loading $loadingIncludes
        if ($found.Found) {
            foreach ($ancestorSettings in $found.Settings) {
                $layers.Add($ancestorSettings)
            }
        }
    }
    if ($Entry -is [System.Collections.IDictionary] -and $Entry._settings) {
        $layers.Add($Entry._settings)
    }

    $settings = $BaseSettings
    foreach ($layer in $layers) {
        $settings = New-ConfigMapSettings -BaseSettings $settings -Overrides $layer
    }
    return $settings
}

function Get-ConfigMapSettings {
    return $script:ConfigMapSettings
}

function Get-ConfigMapBaseSettings {
    return $script:ConfigMapBaseSettings
}

function Get-ConfigMapSettingsForPath {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Map,
        [string]$Path,
        [hashtable]$OperationContext
    )

    $operationContext = if ($OperationContext) { $OperationContext } else { New-ConfigMapOperationContext }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return Resolve-ConfigMapEntrySettings -BaseSettings $script:ConfigMapBaseSettings -Map $Map -OperationContext $operationContext
    }

    # Match qbuild: foo.all inspects the parent entry's effective settings.
    $entryKey = if ($Path -match '^(.*)\.all$') { $Matches[1] } else { $Path }
    $targets = @(Get-MapEntries $Map $entryKey -language 'build' -OperationContext $operationContext)
    if ($targets.Count -eq 0) {
        throw "Entry '$Path' not found."
    }

    return Resolve-ConfigMapEntrySettings `
        -BaseSettings $script:ConfigMapBaseSettings `
        -Map $Map `
        -EntryKey $entryKey `
        -Entry $targets[0].Value `
        -OperationContext $operationContext
}

function Get-ConfigMapSetting {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        # Defaults to the current settings, for map scripts and plugin hooks.
        $Settings
    )

    # Hook contexts built outside qbuild may carry no Settings.
    if ($null -eq $Settings) {
        $Settings = Get-ConfigMapSettings
    }
    return $Settings.PSObject.Properties[$Name].Value
}

function Test-ConfigMapFeatureEnabled {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('TmuxAutoWindow', 'Concurrently', 'DiscoveryCache', 'ForceCheck', 'UseWorkDir')]
        [string]$Name,
        # Defaults to the current settings, for map scripts and plugin hooks.
        $Settings
    )

    switch (Get-ConfigMapSetting -Name $Name -Settings $Settings) {
        $true { return $true }
        { $_ -in '1', 'true', 'yes', 'on' } { return $true }
        default { return $false }
    }
}

Update-ConfigMapSettings | Out-Null
