$script:ConfigMapPlugins = @()

function Invoke-ConfigMapPluginHooks {
    param(
        [string]$HookName,
        [hashtable]$Context
    )

    foreach ($plugin in $script:ConfigMapPlugins) {
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
