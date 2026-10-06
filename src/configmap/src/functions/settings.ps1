$script:ConfigMapSettings = $null

function New-ConfigMapSettings {
    param(
        $BaseSettings,
        [System.Collections.IDictionary]$Overrides = @{}
    )

    $settings = @{
        Debug          = $false
        Concurrently   = $false
        TmuxAutoWindow = $false
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

    $settingsObject = [pscustomobject]$settings
    $settingsObject.PSObject.TypeNames.Insert(0, 'ConfigMap.Settings')

    return $settingsObject
}

function Update-ConfigMapSettings {
    $script:ConfigMapSettings = New-ConfigMapSettings

    return $script:ConfigMapSettings
}

function Enter-ConfigMapSettingsScope {
    param(
        [System.Collections.IDictionary]$Settings
    )

    $previousSettings = $script:ConfigMapSettings
    if ($Settings) {
        $script:ConfigMapSettings = New-ConfigMapSettings -BaseSettings $previousSettings -Overrides $Settings
    }

    return $previousSettings
}

function Exit-ConfigMapSettingsScope {
    param($PreviousSettings)

    $script:ConfigMapSettings = $PreviousSettings
}

function New-ConfigMapOperationContext {
    return @{
        IncludeCache    = @{}
        LoadingIncludes = @{}
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
        if (-not $usePrefix -or $inc.Key -ne $segment) {
            continue
        }

        $included = Import-IncludedConfigMap -DirectoryName "$($inc.Key)" -BaseDir $baseDir -Cache $Cache -Loading $Loading
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

        $included = Import-IncludedConfigMap -DirectoryName "$($inc.Key)" -BaseDir $baseDir -Cache $Cache -Loading $Loading
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

function Enter-ConfigMapAncestorSettingsScopes {
    param(
        [System.Collections.IDictionary]$Map,
        [string]$EntryKey,
        [switch]$IncludeTarget,
        [hashtable]$OperationContext
    )

    $entered = [System.Collections.Generic.List[object]]::new()
    try {
        $segments = @($EntryKey -split '\.')
        $visited = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $includeCache = if ($OperationContext) { $OperationContext.IncludeCache } else { @{} }
        $loadingIncludes = if ($OperationContext) { $OperationContext.LoadingIncludes } else { @{} }
        $found = Find-ConfigMapAncestorSettings -Node $Map -Segments $segments -IncludeTarget:$IncludeTarget -Visited $visited -Cache $includeCache -Loading $loadingIncludes
        if ($found.Found) {
            foreach ($settings in $found.Settings) {
                $entered.Add((Enter-ConfigMapSettingsScope -Settings $settings))
            }
        }
    }
    catch {
        Exit-ConfigMapSettingsScopes -Scopes $entered
        throw
    }

    foreach ($scope in $entered) {
        ,$scope
    }
}

function Invoke-WithEntrySettings {
    param(
        [System.Collections.IDictionary]$Map,
        [string]$EntryKey,
        $Entry,
        [hashtable]$OperationContext,
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    # Parameter names would hide the caller's $map and $entry from the scriptblock.
    $settingsMap = $Map
    $settingsEntryKey = $EntryKey
    $settingsEntry = $Entry
    $settingsScript = $ScriptBlock
    $settingsOperationContext = $OperationContext
    Remove-Variable Map, EntryKey, Entry, OperationContext, ScriptBlock -ErrorAction SilentlyContinue

    $scopes = [System.Collections.Generic.List[object]]::new()
    try {
        $mapSettings = $null
        if ($settingsMap -is [System.Collections.IDictionary]) {
            $mapSettings = $settingsMap._settings
        }
        $scopes.Add((Enter-ConfigMapSettingsScope -Settings $mapSettings))

        if (-not [string]::IsNullOrEmpty($settingsEntryKey)) {
            $ancestorScopes = @(Enter-ConfigMapAncestorSettingsScopes -Map $settingsMap -EntryKey $settingsEntryKey -OperationContext $settingsOperationContext)
            foreach ($ancestorScope in $ancestorScopes) {
                $scopes.Add($ancestorScope)
            }
        }

        $leafSettings = $null
        if ($settingsEntry -is [System.Collections.IDictionary]) {
            $leafSettings = $settingsEntry._settings
        }
        $scopes.Add((Enter-ConfigMapSettingsScope -Settings $leafSettings))

        & $settingsScript
    }
    finally {
        Exit-ConfigMapSettingsScopes -Scopes $scopes
    }
}

function Exit-ConfigMapSettingsScopes {
    param($Scopes)

    for ($index = $Scopes.Count - 1; $index -ge 0; $index--) {
        Exit-ConfigMapSettingsScope -PreviousSettings $Scopes[$index]
    }
}

function Get-ConfigMapSettings {
    return $script:ConfigMapSettings
}

function Get-ConfigMapSettingsForPath {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Map,
        [string]$Path
    )

    $settings = Get-ConfigMapSettings
    $current = $Map

    if ($current._settings) {
        $settings = New-ConfigMapSettings -BaseSettings $settings -Overrides $current._settings
    }

    $segments = @($Path -split '\.' | Where-Object { $_ })
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $current = $current[$segments[$index]]
        if ($null -eq $current) {
            throw "Entry '$Path' not found."
        }

        if ($current -is [System.Collections.IDictionary] -and $current._settings) {
            $settings = New-ConfigMapSettings -BaseSettings $settings -Overrides $current._settings
        }

        if ($index -lt $segments.Count - 1 -and $current -isnot [System.Collections.IDictionary]) {
            throw "Entry '$Path' not found."
        }
    }

    return $settings
}

function Get-ConfigMapSetting {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $settings = Get-ConfigMapSettings
    return $settings.PSObject.Properties[$Name].Value
}

function Test-ConfigMapFeatureEnabled {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('TmuxAutoWindow', 'Concurrently')]
        [string]$Name
    )

    switch (Get-ConfigMapSetting -Name $Name) {
        $true { return $true }
        { $_ -in '1', 'true', 'yes', 'on' } { return $true }
        default { return $false }
    }
}

Update-ConfigMapSettings | Out-Null
