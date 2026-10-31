BeforeAll {
    $script:discoveryCacheEnvBackup = (Get-Item -Path env:QCONF_DiscoveryCache -ErrorAction SilentlyContinue).Value
    $script:discoveryCacheLocationEnvBackup = (Get-Item -Path env:QCONF_DiscoveryCacheLocation -ErrorAction SilentlyContinue).Value
    Remove-Item -Path env:QCONF_DiscoveryCache -ErrorAction SilentlyContinue
    Remove-Item -Path env:QCONF_DiscoveryCacheLocation -ErrorAction SilentlyContinue

    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force
}

AfterAll {
    Remove-Item -Path env:QCONF_DiscoveryCache -ErrorAction SilentlyContinue
    Remove-Item -Path env:QCONF_DiscoveryCacheLocation -ErrorAction SilentlyContinue
    if ($null -ne $script:discoveryCacheEnvBackup) {
        Set-Item -Path env:QCONF_DiscoveryCache -Value $script:discoveryCacheEnvBackup
    }
    if ($null -ne $script:discoveryCacheLocationEnvBackup) {
        Set-Item -Path env:QCONF_DiscoveryCacheLocation -Value $script:discoveryCacheLocationEnvBackup
    }
    & (Get-Module ConfigMap) { Update-ConfigMapSettings | Out-Null }
}

Describe 'qbuild !cache' {
    BeforeEach {
        & (Get-Module ConfigMap) { Clear-ConfigMapDiscoveryCacheMemory }
        $script:tempRoot = Join-Path $TestDrive "qbuild-cache-$(New-Guid)"
        New-Item -ItemType Directory -Force -Path $script:tempRoot | Out-Null
        @'
@{
    build = @{
        exec = { "build" }
        description = "Build"
    }
    clean = { "clean" }
}
'@ | Set-Content -Path (Join-Path $script:tempRoot '.build.map.ps1')
    }

    It 'returns status for the local map after a cache miss has written the file' {
        Push-Location $script:tempRoot
        try {
            $null = qbuild list
            $result = qbuild '!cache' -Porcelain

            $result.Action | Should -Be 'status'
            $result.Enabled | Should -BeTrue
            $result.Location | Should -Be 'local'
            $result.Exists | Should -BeTrue
            $result.Valid | Should -BeTrue
            $result.Source | Should -Be 'memory'
            $result.Language | Should -Be 'build'
            $result.Path | Should -Be (Join-Path $script:tempRoot '.configmap\discovery.build.cache.json')
            $result.EntryCount | Should -BeGreaterThan 0
            Test-Path $result.Path | Should -BeTrue
        }
        finally {
            Pop-Location
        }
    }

    It 'bare !cache matches !cache.status' {
        Push-Location $script:tempRoot
        try {
            $null = qbuild list
            $implicit = qbuild '!cache' -Porcelain
            $explicit = qbuild '!cache.status' -Porcelain

            $implicit.Action | Should -Be 'status'
            $explicit.Action | Should -Be 'status'
            $explicit.Path | Should -Be $implicit.Path
        }
        finally {
            Pop-Location
        }
    }

    It 'clears the JSON file and later status shows Exists = $false' {
        Push-Location $script:tempRoot
        try {
            $null = qbuild list
            $cachePath = Join-Path $script:tempRoot '.configmap\discovery.build.cache.json'
            Test-Path $cachePath | Should -BeTrue

            $cleared = qbuild '!cache.clear' -Porcelain
            $cleared.Action | Should -Be 'clear'
            $cleared.Exists | Should -BeFalse
            $cleared.Valid | Should -BeFalse
            $cleared.Source | Should -Be 'none'
            Test-Path $cachePath | Should -BeFalse

            $status = qbuild '!cache' -Porcelain
            $status.Exists | Should -BeFalse
            $status.Source | Should -Be 'none'
        }
        finally {
            Pop-Location
        }
    }

    It 'rebuilds after a map edit so new entries appear' {
        Push-Location $script:tempRoot
        try {
            $null = qbuild list
            $before = qbuild '!cache' -Porcelain

            Set-Content -Path (Join-Path $script:tempRoot '.build.map.ps1') -Value @'
@{
    build = { "build" }
    clean = { "clean" }
    test  = { "test" }
}
'@

            $rebuilt = qbuild '!cache.rebuild' -Porcelain
            $rebuilt.Action | Should -Be 'rebuild'
            $rebuilt.Exists | Should -BeTrue
            $rebuilt.Valid | Should -BeTrue
            $rebuilt.Source | Should -Be 'memory'
            $rebuilt.EntryCount | Should -BeGreaterThan $before.EntryCount

            $cache = Get-Content -LiteralPath $rebuilt.Path -Raw | ConvertFrom-Json
            @($cache.entries.hierarchical).key | Should -Contain 'test'
        }
        finally {
            Pop-Location
        }
    }

    It 'prints a summary and returns nothing without -Porcelain' {
        Push-Location $script:tempRoot
        try {
            $null = qbuild list
            $cachePath = Join-Path $script:tempRoot '.configmap\discovery.build.cache.json'

            qbuild '!cache' 6>$null | Should -BeNullOrEmpty

            $status = qbuild '!cache' 6>&1 | Out-String
            $status | Should -Match 'Discovery cache'
            $status | Should -Match 'valid \(memory\)'
            $status | Should -Match ([regex]::Escape($cachePath))
            $status | Should -Match 'Entries'

            $rebuilt = qbuild '!cache.rebuild' 6>&1 | Out-String
            $rebuilt | Should -Match 'Discovery cache rebuilt'

            $cleared = qbuild '!cache.clear' 6>&1 | Out-String
            $cleared | Should -Match 'Discovery cache cleared'
            $cleared | Should -Match 'missing'
            $cleared | Should -Not -Match 'Entries'
            Test-Path $cachePath | Should -BeFalse
        }
        finally {
            Pop-Location
        }
    }

    It 'rejects the old action forms instead of falling back to status' {
        Push-Location $script:tempRoot
        try {
            $null = qbuild list
            $cachePath = Join-Path $script:tempRoot '.configmap\discovery.build.cache.json'

            { qbuild '!cache' 'clear' } | Should -Throw -ExpectedMessage '*!cache.clear*'
            { qbuild '!cache' -Action clear } | Should -Throw -ExpectedMessage '*!cache.clear*'
            Test-Path $cachePath | Should -BeTrue
        }
        finally {
            Pop-Location
        }
    }

    It 'rejects extra arguments on subcommands' {
        Push-Location $script:tempRoot
        try {
            { qbuild '!cache.clear' 'rebuild' } | Should -Throw -ExpectedMessage '*takes no arguments*'
        }
        finally {
            Pop-Location
        }
    }

    It 'throws when map is missing' {
        $emptyDir = Join-Path $TestDrive 'no-map-cache'
        New-Item -ItemType Directory -Force -Path $emptyDir | Out-Null
        Push-Location $emptyDir
        try {
            { qbuild '!cache' } | Should -Throw -ExpectedMessage '*No build map file found*'
        }
        finally {
            Pop-Location
        }
    }

    It 'includes !cache in entry completions when a map exists' {
        Push-Location $script:tempRoot
        try {
            $completer = (Get-Command qbuild).Parameters['entry'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
                Select-Object -First 1

            $completions = & $completer.ScriptBlock 'qbuild' 'entry' '' $null @{}
            $completions | Should -Contain '!cache'
        }
        finally {
            Pop-Location
        }
    }

    It 'includes !cache in entry completions without a build map' {
        $emptyDir = Join-Path $TestDrive 'no-map-cache-complete'
        New-Item -ItemType Directory -Force -Path $emptyDir | Out-Null
        Push-Location $emptyDir
        try {
            $completer = (Get-Command qbuild).Parameters['entry'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
                Select-Object -First 1

            $completions = & $completer.ScriptBlock 'qbuild' 'entry' '!ca' $null @{}
            $completions | Should -Contain '!cache'
        }
        finally {
            Pop-Location
        }
    }

    It 'includes !cache subcommands in entry completions' {
        Push-Location $script:tempRoot
        try {
            $completer = (Get-Command qbuild).Parameters['entry'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
                Select-Object -First 1

            $completions = & $completer.ScriptBlock 'qbuild' 'entry' '!cache.' $null @{}
            $completions | Should -Be @('!cache.status', '!cache.clear', '!cache.rebuild')
        }
        finally {
            Pop-Location
        }
    }

    It 'exposes only -Porcelain for <key>' -ForEach @(
        @{ key = '!cache' }
        @{ key = '!cache.status' }
        @{ key = '!cache.clear' }
        @{ key = '!cache.rebuild' }
    ) {
        InModuleScope ConfigMap -Parameters @{ key = $key } {
            $map = Merge-ConfigMapCommands -Language build
            $params = Get-EntryDynamicParam -map $map -key $key -command exec
            @($params.Keys) | Should -Be @('Porcelain')
            $params['Porcelain'].ParameterType | Should -Be ([switch])
        }
    }

    It 'reports user cache path when DiscoveryCacheLocation is user' {
        $userHome = Join-Path $TestDrive 'qbuild-cache-user-home'
        New-Item -ItemType Directory -Force -Path $userHome | Out-Null
        Set-Content -Path (Join-Path $script:tempRoot '.build.map.ps1') -Value @'
@{
    _settings = @{ DiscoveryCacheLocation = 'user' }
    build = { "build" }
}
'@

        $previousHome = $env:HOME
        $env:HOME = $userHome
        Push-Location $script:tempRoot
        try {
            $result = qbuild '!cache.rebuild' -Porcelain
            $result.Location | Should -Be 'user'
            $result.Exists | Should -BeTrue
            $result.Path | Should -Match '\\.configmap\\'
            $result.Path | Should -BeLike "$userHome*"
            Test-Path (Join-Path $script:tempRoot '.configmap') | Should -BeFalse
        }
        finally {
            Pop-Location
            if ($null -eq $previousHome) {
                Remove-Item env:HOME -ErrorAction SilentlyContinue
            }
            else {
                $env:HOME = $previousHome
            }
        }
    }

    It 'reports Enabled = $false, throws on rebuild, and still clears leftover files when disabled' {
        Push-Location $script:tempRoot
        try {
            $null = qbuild list
            $cachePath = Join-Path $script:tempRoot '.configmap\discovery.build.cache.json'
            Test-Path $cachePath | Should -BeTrue

            $previous = $env:QCONF_DiscoveryCache
            $env:QCONF_DiscoveryCache = '0'
            try {
                & (Get-Module ConfigMap) { Update-ConfigMapSettings | Out-Null }

                $status = qbuild '!cache' -Porcelain
                $status.Enabled | Should -BeFalse
                $status.Exists | Should -BeTrue

                { qbuild '!cache.rebuild' } | Should -Throw -ExpectedMessage '*disabled*'

                $cleared = qbuild '!cache.clear' -Porcelain
                $cleared.Enabled | Should -BeFalse
                $cleared.Exists | Should -BeFalse
                Test-Path $cachePath | Should -BeFalse
            }
            finally {
                if ($null -eq $previous) {
                    Remove-Item env:QCONF_DiscoveryCache -ErrorAction SilentlyContinue
                }
                else {
                    $env:QCONF_DiscoveryCache = $previous
                }
                & (Get-Module ConfigMap) { Update-ConfigMapSettings | Out-Null }
            }
        }
        finally {
            Pop-Location
        }
    }
}
