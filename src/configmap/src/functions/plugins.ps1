$script:ConfigMapPlugins = @()

function Import-ConfigMapPlugins {
    param([string]$PluginsPath)

    $script:ConfigMapPlugins = @()

    if (-not (Test-Path $PluginsPath)) {
        return
    }

    Get-ChildItem -Path $PluginsPath -Directory | ForEach-Object {
        $pluginFile = Join-Path $_.FullName '_plugin.ps1'
        if (-not (Test-Path $pluginFile)) {
            return
        }

        $plugin = . $pluginFile
        if ($plugin -isnot [hashtable]) {
            Write-Warning "Plugin '$($_.Name)' must return a hashtable from _plugin.ps1"
            return
        }

        if (-not $plugin.name) {
            $plugin.name = $_.Name
        }

        $script:ConfigMapPlugins += $plugin
    }
}

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
