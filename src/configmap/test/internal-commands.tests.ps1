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
                '!settings'
                '!describe'
                '!cache'
            )
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
