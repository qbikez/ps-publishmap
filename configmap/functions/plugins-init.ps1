param([string]$PluginsPath)

$script:ConfigMapPlugins = @()
$script:ConfigMapValuePrefixes = @{}

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

    $plugin.path = $pluginDir.FullName
    $script:ConfigMapPlugins += $plugin
}

# Register after sorting so that on a duplicate prefix the lower priority number wins.
$byPriority = $script:ConfigMapPlugins | Sort-Object { if ($null -ne $_.priority) { $_.priority } else { 100 } }
foreach ($plugin in $byPriority) {
    if ($plugin.valuePrefixes) { Register-ConfigMapValuePrefix $plugin }
}
