param([string]$PluginsPath)

$script:ConfigMapPlugins = @()

if (-not (Test-Path $PluginsPath)) {
    return
}

foreach ($pluginDir in Get-ChildItem -Path $PluginsPath -Directory) {
    $pluginFile = Join-Path $pluginDir.FullName '_plugin.ps1'
    if (-not (Test-Path $pluginFile)) {
        continue
    }

    $plugin = . $pluginFile
    if ($plugin -isnot [hashtable]) {
        Write-Warning "Plugin '$($pluginDir.Name)' must return a hashtable from _plugin.ps1"
        continue
    }

    if (-not $plugin.name) {
        $plugin.name = $pluginDir.Name
    }

    $script:ConfigMapPlugins += $plugin
}
