function New-ConfigMapRunContext {
    <#
    .SYNOPSIS
        Context for one qbuild, qrun or qconf invocation: the map, its operation caches, and the
        map-level settings resolved from the module's base settings. Nothing is inherited from a caller.
    #>
    param(
        [System.Collections.IDictionary]$Map,
        [hashtable]$OperationContext,
        $BaseSettings = $script:ConfigMapBaseSettings
    )

    if (-not $OperationContext) {
        $OperationContext = New-ConfigMapOperationContext
    }

    return @{
        BaseSettings = $BaseSettings
        Settings     = Resolve-ConfigMapEntrySettings -BaseSettings $BaseSettings -Map $Map -OperationContext $OperationContext
        Map          = $Map
        Operation    = $OperationContext
        EntryKey     = ''
        Entry        = $null
    }
}

function New-ConfigMapEntryContext {
    <#
    .SYNOPSIS
        Child context for an entry. -EntryKey is a full path in the parent's map. With -Map, it is
        relative to that sub-entry instead, and settings build on the parent's (exec arrays).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parent,
        [string]$EntryKey,
        $Entry,
        [System.Collections.IDictionary]$Map
    )

    $context = $Parent.Clone()
    $context.Entry = $Entry
    if ($Map) {
        $context.Settings = Resolve-ConfigMapEntrySettings `
            -BaseSettings $Parent.Settings `
            -Map $Map `
            -EntryKey $EntryKey `
            -Entry $Entry `
            -OperationContext $Parent.Operation
        $context.EntryKey = if ($Parent.EntryKey) { "$($Parent.EntryKey).$EntryKey" } else { $EntryKey }
        return $context
    }

    $context.Settings = Resolve-ConfigMapEntrySettings `
        -BaseSettings $Parent.BaseSettings `
        -Map $Parent.Map `
        -EntryKey $EntryKey `
        -Entry $Entry `
        -OperationContext $Parent.Operation
    $context.EntryKey = $EntryKey
    return $context
}

function Invoke-WithRunContext {
    <#
    .SYNOPSIS
        Run a scriptblock with the context's settings as the current settings. Map scripts and
        plugin hooks read them through Get-ConfigMapSetting.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    # Parameter names would hide the caller's $context from the scriptblock.
    $runSettings = $Context.Settings
    $runScript = $ScriptBlock
    Remove-Variable Context, ScriptBlock -ErrorAction SilentlyContinue

    $previousSettings = $script:ConfigMapSettings
    $script:ConfigMapSettings = $runSettings
    try {
        & $runScript
    }
    finally {
        $script:ConfigMapSettings = $previousSettings
    }
}

function ConvertTo-ConfigMapReadOnlySettings {
    <#
    .SYNOPSIS
        Read-only snapshot of a settings object, exposed to scripts as $_context.settings.
    #>
    param(
        [Parameter(Mandatory)]
        $Settings
    )

    $copy = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($property in $Settings.PSObject.Properties) {
        $copy[$property.Name] = $property.Value
    }
    return [System.Collections.ObjectModel.ReadOnlyDictionary[string, object]]::new($copy)
}
