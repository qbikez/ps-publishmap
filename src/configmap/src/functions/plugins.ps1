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
