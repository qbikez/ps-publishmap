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

    It 'restores nested settings scopes in LIFO order' {
        InModuleScope ConfigMap {
            $scope1 = Enter-ConfigMapSettingsScope -Settings @{ Debug = 'scope1'; Concurrently = 'scope1' }
            try {
                Get-ConfigMapSetting -Name Debug | Should -Be 'scope1'
                Get-ConfigMapSetting -Name Concurrently | Should -Be 'scope1'

                $scope2 = Enter-ConfigMapSettingsScope -Settings @{ Concurrently = 'scope2' }
                try {
                    Get-ConfigMapSetting -Name Debug | Should -Be 'scope1'
                    Get-ConfigMapSetting -Name Concurrently | Should -Be 'scope2'

                    $scope3 = Enter-ConfigMapSettingsScope -Settings @{ Debug = 'scope3' }
                    try {
                        Get-ConfigMapSetting -Name Debug | Should -Be 'scope3'
                        Get-ConfigMapSetting -Name Concurrently | Should -Be 'scope2'
                    }
                    finally {
                        Exit-ConfigMapSettingsScope -PreviousSettings $scope3
                    }

                    Get-ConfigMapSetting -Name Debug | Should -Be 'scope1'
                    Get-ConfigMapSetting -Name Concurrently | Should -Be 'scope2'
                }
                finally {
                    Exit-ConfigMapSettingsScope -PreviousSettings $scope2
                }

                Get-ConfigMapSetting -Name Debug | Should -Be 'scope1'
                Get-ConfigMapSetting -Name Concurrently | Should -Be 'scope1'
            }
            finally {
                Exit-ConfigMapSettingsScope -PreviousSettings $scope1
            }
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

    It 'refreshes every setting and retains defaults for unset environment variables' {
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

    It 'returns the current settings object for qbuild !settings' {
        InModuleScope ConfigMap {
            $settings = qbuild '!settings'

            $settings.PSTypeNames | Should -Contain 'ConfigMap.Settings'
            $settings.Debug | Should -Be $false
            $settings.Concurrently | Should -Be $false
            $settings.TmuxAutoWindow | Should -Be $false
        }
    }

    It 'returns settings inherited by an optional qbuild !settings command path' {
        InModuleScope ConfigMap {
            $map = @{
                _settings = @{ Debug = $true }
                my        = @{
                    _settings = @{ Concurrently = $true }
                    something = { Write-Host 'doing something' }
                }
            }

            $rootSettings = qbuild -map $map '!settings'
            $pathSettings = qbuild -map $map '!settings' 'my.something'

            $rootSettings.Debug | Should -Be $true
            $rootSettings.Concurrently | Should -Be $false
            $pathSettings.Debug | Should -Be $true
            $pathSettings.Concurrently | Should -Be $true
        }
    }

    It 'includes qbuild !settings in entry completions without a build map' {
        $completer = (Get-Command qbuild).Parameters['entry'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
            Select-Object -First 1

        $completions = & $completer.ScriptBlock 'qbuild' 'entry' '!set' $null @{}

        $completions | Should -Contain '!settings'
    }

    It 'makes map-level settings available to build scripts without leaking them' {
        InModuleScope ConfigMap {
            $map = @{
                _settings      = @{ TmuxAutoWindow = $true }
                'do_something' = {
                    Get-ConfigMapSetting -Name TmuxAutoWindow
                }
            }

            qbuild -map $map 'do_something' | Should -Be $true
            Get-ConfigMapSetting -Name TmuxAutoWindow | Should -Be $false
        }
    }

    It 'respect children settings' {
        InModuleScope ConfigMap {
            $map = @{
                _settings      = @{ TmuxAutoWindow = $true; Debug = 'parent' }
                'do_something' = @{
                    "inner"  = @{
                        _settings = @{ TmuxAutoWindow = $false }
                        "exec"    = {
                            Get-ConfigMapSetting -Name TmuxAutoWindow
                            Get-ConfigMapSetting -Name Debug
                        }
                    }
                    "inner2" = @{
                        _settings = @{ TmuxAutoWindow = $false }
                        "a"       = {
                            Get-ConfigMapSetting -Name TmuxAutoWindow
                            Get-ConfigMapSetting -Name Debug
                        }
                    }
                    "exec"   = {
                        Get-ConfigMapSetting -Name TmuxAutoWindow
                    }
                }
            }

            qbuild -map $map 'do_something' | Should -Be $true
            qbuild -map $map 'do_something.inner' | Should -Be @($false, 'parent')
            qbuild -map $map 'do_something.inner2.a' | Should -Be @($false, 'parent')
            qbuild -map $map 'do_something.inner2.all' | Should -Be @($false, 'parent')
        }
    }

    It 'makes child settings available to InvokeEntryWrapper hook' {
        InModuleScope ConfigMap {
            $previousPlugins = $script:ConfigMapPlugins
            $script:entryPluginSetting = $null
            $script:ConfigMapPlugins = @(
                @{
                    name  = 'settings-test'
                    hooks = @{
                        InvokeEntryWrapper = {
                            param($context)
                            $tmuxEnabled = Get-ConfigMapSetting -Name TmuxAutoWindow
                            return @{ Handled = $tmuxEnabled }
                        }
                    }
                }
            )

            try {
                $map = @{
                    _settings  = @{ TmuxAutoWindow = $false }
                    notSkipped = {
                        echo "plugin passed through"
                    }
                    child      = @{
                        _settings = @{ TmuxAutoWindow = $true }
                        exec      = {
                            echo "plugin passed through"
                        }
                        "a"       = {
                            echo "plugin passed through"
                        }
                    }
                }

                qbuild -map $map notSkipped | Should -Be "plugin passed through"
                qbuild -map $map child | Should -BeNullOrEmpty
                qbuild -map $map child.a | Should -BeNullOrEmpty
                qbuild -map $map child.all | Should -BeNullOrEmpty
            }
            finally {
                $script:ConfigMapPlugins = $previousPlugins
            }
        }
    }

    It 'makes map settings available to InvokeQBuildTargets hook' {
        InModuleScope ConfigMap {
            $previousPlugins = $script:ConfigMapPlugins
            $script:ConfigMapPlugins = @(
                @{
                    name  = 'settings-test'
                    hooks = @{
                        InvokeQBuildTargets = {
                            param($context)
                            $tmuxEnabled = Get-ConfigMapSetting -Name TmuxAutoWindow
                            return @{ Handled = $tmuxEnabled }
                        }
                    }
                }
            )

            try {
                $map = @{
                    _settings = @{ TmuxAutoWindow = $false }
                    build     = {
                        echo "plugin passed through"
                    }
                    child     = @{
                        _settings = @{ TmuxAutoWindow = $true }
                        exec      = {
                            echo "plugin passed through"
                        }
                        "a"       = {
                            echo "plugin passed through"
                        }
                    }
                }
                qbuild -map $map build | Should -Be "plugin passed through"
                qbuild -map $map child | Should -BeNullOrEmpty
                qbuild -map $map child.a | Should -BeNullOrEmpty
                qbuild -map $map child.all | Should -BeNullOrEmpty
            }
            finally {
                $script:ConfigMapPlugins = $previousPlugins
            }
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

    It 'restores settings when a build script throws' {
        InModuleScope ConfigMap {
            $map = @{
                _settings = @{ Debug = 'map' }
                build     = { throw 'boom' }
            }

            { qbuild -map $map build } | Should -Throw 'boom'
            Get-ConfigMapSetting -Name Debug | Should -Be $false
        }
    }

    It 'applies an exec subcommand''s own settings' {
        InModuleScope ConfigMap {
            $map = @{
                _settings = @{ Debug = 'map' }
                build     = @{
                    _settings = @{ Debug = 'parent' }
                    exec      = @('frontend', 'backend')
                    frontend  = @{
                        _settings = @{ Debug = 'front' }
                        exec      = { Get-ConfigMapSetting -Name Debug }
                    }
                    backend   = @{
                        _settings = @{ Debug = 'back' }
                        exec      = { Get-ConfigMapSetting -Name Debug }
                    }
                }
            }

            qbuild -map $map build | Should -Be @('front', 'back')
            Get-ConfigMapSetting -Name Debug | Should -Be $false
        }
    }

    It 'applies ancestor settings for a nested configuration entry' {
        InModuleScope ConfigMap {
            $map = @{
                _settings = @{ Debug = 'map'; Concurrently = $true }
                group     = @{
                    _settings = @{ Debug = 'group' }
                    sample    = @{
                        _settings = @{ Concurrently = $false }
                        get       = {
                            "$(Get-ConfigMapSetting -Name Debug)|$(Get-ConfigMapSetting -Name Concurrently)"
                        }
                    }
                }
            }

            $result = qconf -command get -entry group.sample -map $map

            $result.Value | Should -Be 'group|False'
            Get-ConfigMapSetting -Name Debug | Should -Be $false
            Get-ConfigMapSetting -Name Concurrently | Should -Be $false
        }
    }
}

Describe 'included map settings' {
    BeforeAll {
        $script:includeRoot = Join-Path $TestDrive 'settings-include'
        $childDir = Join-Path $script:includeRoot 'child'
        New-Item -ItemType Directory -Path $childDir -Force | Out-Null
        Set-Content -Encoding utf8 -Path (Join-Path $childDir '.build.map.ps1') @'
@{
    _settings = @{ Debug = 'included' }
    group = @{
        _settings = @{ TmuxAutoWindow = $true }
        task = {
            $debug = Get-ConfigMapSetting -Name Debug
            $tmux = Get-ConfigMapSetting -Name TmuxAutoWindow
            $concurrent = Get-ConfigMapSetting -Name Concurrently
            "$debug|$tmux|$concurrent"
        }
    }
}
'@
    }

    It 'applies root, included, and group settings for a prefixed include' {
        InModuleScope ConfigMap -ArgumentList $script:includeRoot {
            param($Root)
            $map = @{
                _baseDir   = $Root
                _settings  = @{ Debug = 'root'; Concurrently = $true }
                '#include' = @{
                    child = @{ prefix = $true }
                }
            }

            qbuild -map $map 'child.group.task' | Should -Be 'included|True|True'
            Get-ConfigMapSetting -Name Debug | Should -Be $false
            Get-ConfigMapSetting -Name Concurrently | Should -Be $false
        }
    }

    It 'applies included map settings when the include has no prefix' {
        InModuleScope ConfigMap -ArgumentList $script:includeRoot {
            param($Root)
            $map = @{
                _baseDir   = $Root
                _settings  = @{ Debug = 'root'; Concurrently = $true }
                '#include' = @{
                    child = @{ prefix = $false }
                }
            }

            qbuild -map $map 'group.task' | Should -Be 'included|True|True'
            Get-ConfigMapSetting -Name Debug | Should -Be $false
        }
    }
}