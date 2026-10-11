param([string]$PluginsPath)

$script:ConfigMapPlugins = @()
$script:ConfigMapProcesses = @{}

if (-not (Test-Path $PluginsPath)) {
    return
}

foreach ($pluginDir in Get-ChildItem -Path $PluginsPath -Directory) {
    $processFile = Join-Path $pluginDir.FullName '_process.ps1'
    $pluginFile = Join-Path $pluginDir.FullName '_plugin.ps1'

    if ((Test-Path $processFile) -and $pluginDir.Name -like 'process-*') {
        $process = . $processFile
        if ($process -isnot [hashtable] -and $process -isnot [System.Collections.IDictionary]) {
            Write-Warning "Process plugin '$($pluginDir.Name)' must return a hashtable from _process.ps1"
            continue
        }

        if (-not $process.name) {
            $process.name = $pluginDir.Name -replace '^process-', ''
        }

        if (-not $process.Invoke) {
            Write-Warning "Process plugin '$($process.name)' is missing required Invoke member"
            continue
        }

        $script:ConfigMapProcesses[$process.name] = $process
        continue
    }

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
