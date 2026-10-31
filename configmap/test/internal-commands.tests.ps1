BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force
}

Describe 'qbuild internal commands' {
    It 'defines every internal command in one map' {
        InModuleScope ConfigMap {
            $commands = Get-ConfigMapInternalCommands -Language build

            @($commands.Keys) | Should -Be @(
                'help'
                'list'
                '!init'
                '!agent.init'
                '!agent.skills'
                '!extension.install'
                '!settings'
                '!describe'
                '!cache'
            )
        }
    }

    It 'defines list.<type> shorthands as sub-entries of the list command' {
        InModuleScope ConfigMap {
            $map = [ordered]@{
                setting = [ordered]@{ _settings = @{ process = 'options' }; get = { 'x' }; set = { param($_context, $value, $key) }; options = @{ local = 'x' } }
                steps1  = [ordered]@{ _settings = @{ process = 'steps' }; one = { 'one' } }
            }

            $list = (Get-ConfigMapInternalCommands -Language build -Map $map)['list']
            @($list.list.Keys) | Should -Be @('exec', 'qconf', 'qrun')

            $merged = Merge-ConfigMapCommands -Map $map -Language build
            (Get-MapEntry $merged 'list.qconf' -language build).exec | Should -BeOfType ([scriptblock])
            (Get-MapEntry $merged 'list.exec' -language build).exec | Should -BeOfType ([scriptblock])
            Test-ConfigMapInternalCommand -Name 'list.qconf' -Language build | Should -BeTrue
            Test-ConfigMapInternalCommand -Name 'nope.qconf' -Language build | Should -BeFalse
        }
    }

    It 'lists internal command paths including list.<type>' {
        InModuleScope ConfigMap {
            $map = [ordered]@{ steps1 = [ordered]@{ _settings = @{ process = 'steps' }; one = { 'one' } } }

            $paths = Get-ConfigMapInternalCommandPaths -Map $map
            @($paths.Keys) | Should -Contain 'list'
            @($paths.Keys) | Should -Contain 'list.exec'
            @($paths.Keys) | Should -Contain 'list.qrun'
            @($paths.Keys) | Should -Not -Contain 'list.qconf'
        }
    }

    It 'keeps user commands while internal commands win name collisions' {
        InModuleScope ConfigMap {
            $userBuild = { 'user build' }
            $userCache = { 'user cache' }
            $userList = { 'user list' }
            $map = [ordered]@{
                list = [ordered]@{
                    build    = $userBuild
                    nested   = { 'nested' }
                    '!cache' = $userCache
                    list     = $userList
                }
            }

            $merged = Merge-ConfigMapCommands -Map $map -Language build

            (Get-MapEntry $merged 'build' -language build) | Should -Be $userBuild
            (Get-MapEntry $merged 'nested' -language build) | Should -Not -BeNullOrEmpty
            (Get-MapEntry $merged '!cache' -language build) | Should -BeOfType ([System.Collections.IDictionary])
            (Get-MapEntry $merged 'list' -language build) | Should -BeOfType ([System.Collections.IDictionary])
            (Get-MapEntry $merged '!cache' -language build).description | Should -Be 'Inspect or manage the discovery cache'
            (Get-MapEntry $merged 'list' -language build).description | Should -Be 'List available build commands'
        }
    }

    It 'lists every internal command and no user commands for qbuild list -Internal' {
        $workDir = Join-Path $TestDrive 'internal-list'
        New-Item -ItemType Directory -Path $workDir | Out-Null
        $localMap = Join-Path $workDir 'mixed.build.map.ps1'
        @'
[ordered]@{
    zeta_user_only = { 'user' }
    steps1 = [ordered]@{ _settings = @{ process = 'steps' }; one = { 'one' } }
    setting = [ordered]@{
        _settings = @{ process = 'options' }
        get = { 'x' }
        set = { param($_context, $value, $key) }
        options = @{ local = 'x' }
    }
}
'@ | Set-Content -LiteralPath $localMap -Encoding utf8

        $output = qbuild -map $localMap list -Internal 6>&1 | Out-String

        $output | Should -Match 'INTERNAL COMMANDS'
        foreach ($name in @(
                'help', 'list', 'list.exec', 'list.qconf', 'list.qrun',
                '!init', '!agent.init', '!agent.skills', '!extension.install',
                '!settings', '!describe', '!cache'
            )) {
            $output | Should -Match ([regex]::Escape($name))
        }
        $output | Should -Match 'List available build commands'
        $output | Should -Match 'List exec entries'
        $output | Should -Match 'List qconf entries'
        $output | Should -Match 'List qrun entries'
        $output | Should -Match '-Type'
        $output | Should -Match '-Internal'
        $output | Should -Match '-Scope'
        $output | Should -Match '-Action'
        $output | Should -Not -Match 'zeta_user_only'

        $plain = qbuild -map $localMap list 6>&1 | Out-String
        $plain | Should -Match 'zeta_user_only'
        $plain | Should -Not -Match '!describe'
        $plain | Should -Not -Match 'INTERNAL COMMANDS'
    }

    It 'lists internal commands when no build map exists' {
        $workDir = Join-Path $TestDrive 'no-map-internal-list'
        New-Item -ItemType Directory -Path $workDir | Out-Null
        Push-Location $workDir
        try {
            $output = qbuild list -Internal 6>&1 5>&1 4>&1 3>&1 2>&1 | Out-String

            $output | Should -Match 'INTERNAL COMMANDS'
            $output | Should -Match '!init'
            $output | Should -Match 'list\.exec'
            $output | Should -Not -Match 'list\.qconf'
            $output | Should -Not -Match 'No build map file found'
        }
        finally {
            Pop-Location
        }
    }

    It 'rejects list -Internal combined with -Type' {
        $workDir = Join-Path $TestDrive 'internal-list-type'
        New-Item -ItemType Directory -Path $workDir | Out-Null
        $localMap = Join-Path $workDir 'map.build.map.ps1'
        "@{ clean = { 'clean' } }" | Set-Content -LiteralPath $localMap -Encoding utf8

        { qbuild -map $localMap list -Internal -Type exec 6>$null } | Should -Throw '*cannot be combined*'
    }

    It 'prints every internal command from help' {
        $output = qbuild help 6>&1 5>&1 4>&1 3>&1 2>&1 | Out-String

        $output | Should -Match 'INTERNAL COMMANDS'
        $output | Should -Match 'help'
        $output | Should -Match 'list'
        $output | Should -Match '!init'
        $output | Should -Match '!agent.init'
        $output | Should -Match '!agent.skills'
        $output | Should -Match '!extension.install'
        $output | Should -Match '!settings'
        $output | Should -Match '!describe'
        $output | Should -Match '!cache'
        $output | Should -Match '-Version'
        $output | Should -Match '-Scope'
        $output | Should -Match '-Agent'
        $output | Should -Match '-Action'
    }

    It 'preserves root map metadata used by settings and file-backed commands' {
        InModuleScope ConfigMap {
            $map = [ordered]@{
                _sourceFile = 'C:\project\.build.map.ps1'
                _baseDir    = 'C:\project'
                _settings   = @{ DiscoveryCache = $false }
                build       = { 'build' }
            }

            $merged = Merge-ConfigMapCommands -Map $map -Language build

            $merged._sourceFile | Should -Be $map._sourceFile
            $merged._baseDir | Should -Be $map._baseDir
            $merged._settings.DiscoveryCache | Should -BeFalse
        }
    }
}

Describe 'qbuild -version' {
    BeforeAll {
        $script:moduleVersion = [string](Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\configmap.psd1')).ModuleVersion
    }

    It 'prints the ConfigMap module version without requiring a map' {
        $result = qbuild -Version

        $result | Should -Match "^qbuild $([regex]::Escape($script:moduleVersion))(-.+)?$"
    }

    It 'appends the git branch when the module is loaded from a github repo' {
        $moduleDir = Join-Path $PSScriptRoot '..'
        $remote = & git -C $moduleDir config --get remote.origin.url 2>$null
        $branch = & git -C $moduleDir rev-parse --abbrev-ref HEAD 2>$null
        if ($remote -notmatch 'github\.com' -or -not $branch -or $branch -eq 'HEAD') {
            Set-ItResult -Skipped -Because 'module is not loaded from a github checkout on a branch'
            return
        }

        qbuild -Version | Should -Be "qbuild $script:moduleVersion-$branch"
    }
}
