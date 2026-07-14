BeforeAll {
    $script:settingsEnvironmentBackup = @{}
    $script:settingsEnvironmentVariables = @(
        'QCONF_TmuxAutoWindow',
        'QCONF_Concurrently',
        'QCONF_Debug'
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
        $env:QCONF_TmuxAutoWindow = '0'
        $env:QCONF_Concurrently = 'false'
        $env:QCONF_Debug = '1'

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
            Get-ConfigMapSetting -Name TmuxAutoWindow | Should -Be $false
            Test-ConfigMapFeatureEnabled -Name TmuxAutoWindow | Should -Be $false
        }

        $env:QCONF_TmuxAutoWindow = '0'

        InModuleScope ConfigMap {
            Get-ConfigMapSetting -Name TmuxAutoWindow | Should -Be $false

            Update-ConfigMapSettings | Out-Null
            Get-ConfigMapSetting -Name TmuxAutoWindow | Should -Be '0'
            Test-ConfigMapFeatureEnabled -Name TmuxAutoWindow | Should -Be $false
        }
    }

    It 'refreshes every setting and retains default values for unset environment variables' {
        $env:QCONF_TmuxAutoWindow = '1'
        $env:QCONF_Concurrently = 'off'

        InModuleScope ConfigMap {
            $settings = Update-ConfigMapSettings

            $settings.TmuxAutoWindow | Should -Be '1'
            $settings.Concurrently | Should -Be 'off'
            $settings.Debug | Should -Be $false
            Test-ConfigMapFeatureEnabled -Name Concurrently | Should -Be $false
        }
    }

    It 'makes map-level settings available to build scripts without leaking them' {
        InModuleScope ConfigMap {
            $map = @{
                _settings      = @{ TmuxAutoWindow = $false }
                'do_something' = {
                    Get-ConfigMapSetting -Name TmuxAutoWindow
                }
            }

            qbuild -map $map 'do_something' | Should -Be $false
            Get-ConfigMapSetting -Name TmuxAutoWindow | Should -Be $false
        }
    }

    It 'uses map-level settings for configuration scripts' {
        InModuleScope ConfigMap {
            $map = @{
                _settings = @{ Debug = 'map-debug' }
                sample    = @{
                    get = {
                        Get-ConfigMapSetting -Name Debug
                    }
                }
            }

            $result = qconf -command get -entry sample -map $map

            $result.Value | Should -Be 'map-debug'
            Get-ConfigMapSetting -Name Debug | Should -Be $false
        }
    }

    It 'does not expose map-level settings as a command' {
        InModuleScope ConfigMap {
            $map = @{
                _settings = @{ TmuxAutoWindow = $false }
                build     = { }
            }

            (Get-CompletionList -map $map -language build).Keys | Should -Be @('build')
        }
    }

    It 'rejects unknown map-level settings' {
        InModuleScope ConfigMap {
            $map = @{
                _settings = @{ Unknown = 'value' }
                build     = { }
            }

            { qbuild -map $map build } | Should -Throw "Unknown ConfigMap setting 'Unknown'."
        }
    }
}