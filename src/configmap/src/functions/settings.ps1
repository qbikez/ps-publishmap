$script:ConfigMapSettings = $null

function New-ConfigMapSettings {
    param(
        $BaseSettings,
        [System.Collections.IDictionary]$Overrides = @{}
    )

    $settings = @{
        Debug          = $false
        Concurrently   = $false
        TmuxAutoWindow = $false
    }

    foreach ($propertyName in @($settings.Keys)) {
        $envPath = "env:QCONF_$propertyName"
        if (Test-Path -Path $envPath) {
            $settings[$propertyName] = (Get-Item -Path $envPath).Value
        }
    }

    if ($BaseSettings) {
        foreach ($propertyName in @($settings.Keys)) {
            $settings[$propertyName] = $BaseSettings.PSObject.Properties[$propertyName].Value
        }
    }

    foreach ($override in $Overrides.GetEnumerator()) {
        if (-not $settings.ContainsKey($override.Key)) {
            throw "Unknown ConfigMap setting '$($override.Key)'."
        }

        $settings[$override.Key] = $override.Value
    }

    $settingsObject = [pscustomobject]$settings
    $settingsObject.PSObject.TypeNames.Insert(0, 'ConfigMap.Settings')

    return $settingsObject
}

function Update-ConfigMapSettings {
    $script:ConfigMapSettings = New-ConfigMapSettings

    return $script:ConfigMapSettings
}

function Enter-ConfigMapSettingsScope {
    param(
        [System.Collections.IDictionary]$Settings
    )

    $previousSettings = $script:ConfigMapSettings
    if ($Settings) {
        $script:ConfigMapSettings = New-ConfigMapSettings -BaseSettings $previousSettings -Overrides $Settings
    }

    return $previousSettings
}

function Exit-ConfigMapSettingsScope {
    param($PreviousSettings)

    $script:ConfigMapSettings = $PreviousSettings
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

    $settings = Get-ConfigMapSettings
    return $settings.PSObject.Properties[$Name].Value
}

function Test-ConfigMapFeatureEnabled {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('TmuxAutoWindow', 'Concurrently')]
        [string]$Name
    )

    switch (Get-ConfigMapSetting -Name $Name) {
        $true { return $true }
        { $_ -in '1', 'true', 'yes', 'on' } { return $true }
        default { return $false }
    }
}

Update-ConfigMapSettings | Out-Null
