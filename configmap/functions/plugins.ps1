$script:ConfigMapPlugins = @()

function Invoke-ConfigMapPluginHooks {
    param(
        [string]$HookName,
        [hashtable]$Context
    )

    $plugins = $script:ConfigMapPlugins | Sort-Object {
        if ($null -ne $_.priority) { $_.priority } else { 100 }
    }

    foreach ($plugin in $plugins) {
        if (-not $plugin.hooks) { continue }

        $hook = $plugin.hooks[$HookName]
        if (-not $hook) { continue }

        $result = & $hook $Context
        if ($result -and $result.Handled) {
            return $result
        }
    }

    return @{ Handled = $false }
}

# Value prefixes (e.g. `bw:`) are declared in the plugin manifest so they can be recognised
# without loading the plugin; its implementation file is loaded on the first resolve.
$script:ConfigMapValuePrefixes = @{}
$script:ConfigMapModule = $ExecutionContext.SessionState.Module

function Register-ConfigMapValuePrefix {
    param([hashtable]$Plugin)

    foreach ($prefix in $Plugin.valuePrefixes.Keys) {
        $existing = $script:ConfigMapValuePrefixes[$prefix]
        if ($existing) {
            Write-Warning "Value prefix '$prefix' of plugin '$($Plugin.name)' is already provided by plugin '$($existing.plugin.name)'. Ignoring it."
            continue
        }
        $script:ConfigMapValuePrefixes[$prefix] = @{
            plugin  = $Plugin
            secret  = [bool]$Plugin.valuePrefixes[$prefix].secret
            resolve = $Plugin.valuePrefixes[$prefix].resolve
        }
    }
}

function Get-ConfigMapValuePrefix {
    param([string]$Prefix)

    if ($Prefix) { return $script:ConfigMapValuePrefixes[$Prefix] }
    return $script:ConfigMapValuePrefixes.Keys
}

function Import-ConfigMapPluginImplementation {
    param([hashtable]$Plugin)

    if (-not $Plugin.implementation -or $Plugin.implementationLoaded) { return }

    $file = Join-Path $Plugin.path $Plugin.implementation
    # The file is dot-sourced in a child scope of the module, so it must declare what it exposes as
    # `function script:name` (and keep state in `$script:`) for it to outlive the load.
    & $script:ConfigMapModule { . $args[0] } $file
    $Plugin.implementationLoaded = $true
}

function Import-ConfigMapPlugin {
    <#
    .SYNOPSIS
        Loads a plugin's implementation by name, for core code that calls its functions directly.
    #>
    param([Parameter(Mandatory = $true)][string]$Name)

    $plugin = $script:ConfigMapPlugins | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $plugin) { throw "Plugin '$Name' not found." }
    Import-ConfigMapPluginImplementation $plugin
}

function Resolve-ConfigMapPluginValue {
    <#
    .SYNOPSIS
        Resolves a value starting with a registered plugin prefix; $null when it is not one or cannot be resolved.
    #>
    param([string]$Value, [hashtable]$Context = @{})

    foreach ($prefix in $script:ConfigMapValuePrefixes.Keys) {
        if (-not $Value.StartsWith($prefix)) { continue }

        $entry = $script:ConfigMapValuePrefixes[$prefix]
        Import-ConfigMapPluginImplementation $entry.plugin
        return & $entry.resolve $Value.Substring($prefix.Length) $Context
    }
    return $null
}

function Get-ConfigMapSecretValuePrefix {
    return @($script:ConfigMapValuePrefixes.Keys | Where-Object { $script:ConfigMapValuePrefixes[$_].secret })
}
