BeforeAll {
    $script:settingsEnvironmentBackup = @{}
    $script:settingsEnvironmentVariables = @(
        'QCONF_TMUX_AUTOWINDOW',
        'QCONF_CONCURRENTLY',
        'QCONF_DEBUG'
    )

    foreach ($name in $script:settingsEnvironmentVariables) {
        $script:settingsEnvironmentBackup[$name] = (Get-Item -Path "env:$name" -ErrorAction SilentlyContinue).Value
        Remove-Item -Path "env:$name" -ErrorAction SilentlyContinue
    }

    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1
}

AfterAll {
    foreach ($name in $script:settingsEnvironmentVariables) {
        Remove-Item -Path "env:$name" -ErrorAction SilentlyContinue

        if ($null -ne $script:settingsEnvironmentBackup[$name]) {
            Set-Item -Path "env:$name" -Value $script:settingsEnvironmentBackup[$name]
        }
    }

    InModuleScope ConfigMap {
        Update-ConfigMapSettings | Out-Null
    }
}

Describe 'ConfigMap settings' {
    BeforeEach {
        foreach ($name in $script:settingsEnvironmentVariables) {
            Remove-Item -Path "env:$name" -ErrorAction SilentlyContinue
        }

        InModuleScope ConfigMap {
            Update-ConfigMapSettings | Out-Null
        }
    }

    It 'constructs the settings object from environment variables during module initialization' {
        $env:QCONF_TMUX_AUTOWINDOW = '0'
        $env:QCONF_CONCURRENTLY = 'false'
        $env:QCONF_DEBUG = '1'

        Get-Module ConfigMap | Remove-Module
        Import-Module $PSScriptRoot\..\configmap.psm1

        InModuleScope ConfigMap {
            $settings = Get-ConfigMapSettings

            $settings.PSTypeNames | Should -Contain 'ConfigMap.Settings'
            $settings.TmuxAutoWindow | Should -Be '0'
            $settings.Concurrently | Should -Be 'false'
            $settings.Debug | Should -Be '1'
        }
    }

    It 'uses the initialized settings object until explicitly refreshed' {
        InModuleScope ConfigMap {
            (Get-ConfigMapSetting -Name TmuxAutoWindow) | Should -BeNullOrEmpty
        }

        $env:QCONF_TMUX_AUTOWINDOW = '0'

        InModuleScope ConfigMap {
            (Get-ConfigMapSetting -Name TmuxAutoWindow) | Should -BeNullOrEmpty

            Update-ConfigMapSettings | Out-Null
            Get-ConfigMapSetting -Name TmuxAutoWindow | Should -Be '0'
            Test-ConfigMapFeatureEnabled -Name TmuxAutoWindow | Should -Be $false
        }
    }

    It 'refreshes every setting and preserves null for unset environment variables' {
        $env:QCONF_TMUX_AUTOWINDOW = '1'
        $env:QCONF_CONCURRENTLY = 'off'

        InModuleScope ConfigMap {
            $settings = Update-ConfigMapSettings

            $settings.TmuxAutoWindow | Should -Be '1'
            $settings.Concurrently | Should -Be 'off'
            $settings.Debug | Should -BeNullOrEmpty
            Test-ConfigMapFeatureEnabled -Name Concurrently | Should -Be $false
        }
    }
}