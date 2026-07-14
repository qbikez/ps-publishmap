$script:ConfigMapSettingDefinitions = @{
    TmuxAutoWindow = @{
        EnvVar = 'QCONF_TMUX_AUTOWINDOW'
        Kind   = 'FeatureToggle'
    }
    Concurrently   = @{
        EnvVar = 'QCONF_CONCURRENTLY'
        Kind   = 'FeatureToggle'
    }
    Debug          = @{
        EnvVar = 'QCONF_DEBUG'
        Kind   = 'Debug'
    }
}

$script:ConfigMapSettings = $null

function Update-ConfigMapSettings {
    $settings = [ordered]@{}

    foreach ($definition in $script:ConfigMapSettingDefinitions.GetEnumerator()) {
        $settings[$definition.Key] = (Get-Item -Path "env:$($definition.Value.EnvVar)" -ErrorAction SilentlyContinue).Value
    }

    $script:ConfigMapSettings = [pscustomobject]$settings
    $script:ConfigMapSettings.PSObject.TypeNames.Insert(0, 'ConfigMap.Settings')

    return $script:ConfigMapSettings
}

function Get-ConfigMapSettings {
    return $script:ConfigMapSettings
}

function Get-ConfigMapSetting {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('TmuxAutoWindow', 'Concurrently', 'Debug')]
        [string]$Name
    )

    $definition = $script:ConfigMapSettingDefinitions[$Name]
    if (-not $definition) {
        throw "Unknown ConfigMap setting '$Name'."
    }

    return (Get-ConfigMapSettings).PSObject.Properties[$Name].Value
}

function Test-ConfigMapFeatureEnabled {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('TmuxAutoWindow', 'Concurrently')]
        [string]$Name
    )

    switch (Get-ConfigMapSetting -Name $Name) {
        { $_ -in '0', 'false', 'no', 'off' } { return $false }
        default { return $true }
    }
}

Update-ConfigMapSettings | Out-Null
