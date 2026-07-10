$script:ConfigMapSettings = @{
    TmuxAutoWindow = @{
        EnvVar = 'QCONF_TMUX_AUTOWINDOW'
        Kind   = 'FeatureToggle'
    }
    Concurrently = @{
        EnvVar = 'QCONF_CONCURRENTLY'
        Kind   = 'FeatureToggle'
    }
    Debug = @{
        EnvVar = 'QCONF_DEBUG'
        Kind   = 'Debug'
    }
}

function Get-ConfigMapSetting {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('TmuxAutoWindow', 'Concurrently', 'Debug')]
        [string]$Name
    )

    $definition = $script:ConfigMapSettings[$Name]
    if (-not $definition) {
        throw "Unknown ConfigMap setting '$Name'."
    }

    # Future settings providers can be chained here before falling back to env vars.
    return (Get-Item -Path "env:$($definition.EnvVar)" -ErrorAction SilentlyContinue).Value
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
