BeforeAll {
    $script:discoveryCacheEnvBackup = (Get-Item -Path env:QCONF_DiscoveryCache -ErrorAction SilentlyContinue).Value
    Remove-Item -Path env:QCONF_DiscoveryCache -ErrorAction SilentlyContinue

    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force
}

AfterAll {
    Remove-Item -Path env:QCONF_DiscoveryCache -ErrorAction SilentlyContinue
    if ($null -ne $script:discoveryCacheEnvBackup) {
        Set-Item -Path env:QCONF_DiscoveryCache -Value $script:discoveryCacheEnvBackup
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
            $result = qbuild '!cache'

            $result.Action | Should -Be 'status'
            $result.Enabled | Should -BeTrue
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

    It 'defaults to status and accepts an explicit status action' {
        Push-Location $script:tempRoot
        try {
            $null = qbuild list
            $implicit = qbuild '!cache'
            $explicit = qbuild '!cache' 'status'

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

            $cleared = qbuild '!cache' 'clear'
            $cleared.Action | Should -Be 'clear'
            $cleared.Exists | Should -BeFalse
            $cleared.Valid | Should -BeFalse
            $cleared.Source | Should -Be 'none'
            Test-Path $cachePath | Should -BeFalse

            $status = qbuild '!cache'
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
            $before = qbuild '!cache'

            Set-Content -Path (Join-Path $script:tempRoot '.build.map.ps1') -Value @'
@{
    build = { "build" }
    clean = { "clean" }
    test  = { "test" }
}
'@

            $rebuilt = qbuild '!cache' 'rebuild'
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

    It 'rebuilds via -Action' {
        Push-Location $script:tempRoot
        try {
            $result = qbuild '!cache' -Action rebuild
            $result.Action | Should -Be 'rebuild'
            $result.Exists | Should -BeTrue
            $result.Valid | Should -BeTrue
        }
        finally {
            Pop-Location
        }
    }

    It 'throws for an unknown action' {
        Push-Location $script:tempRoot
        try {
            { qbuild '!cache' 'bogus' } | Should -Throw -ExpectedMessage '*status*'
        }
        finally {
            Pop-Location
        }
    }

    It 'throws when more than one action is provided' {
        Push-Location $script:tempRoot
        try {
            { qbuild '!cache' 'clear' 'rebuild' } | Should -Throw -ExpectedMessage '*at most one action*'
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

    It 'exposes Action ValidateSet values for !cache' {
        InModuleScope ConfigMap {
            $params = New-QBuildCacheDynamicParam
            @($params.Keys) | Should -Be @('Action')

            $actionSet = $params['Action'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            @($actionSet.ValidValues) | Should -Be @('status', 'clear', 'rebuild')
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

                $status = qbuild '!cache'
                $status.Enabled | Should -BeFalse
                $status.Exists | Should -BeTrue

                { qbuild '!cache' 'rebuild' } | Should -Throw -ExpectedMessage '*disabled*'

                $cleared = qbuild '!cache' 'clear'
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
