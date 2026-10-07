BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force
}

Describe 'Discovery cache' {
    BeforeEach {
        & (Get-Module ConfigMap) { Clear-ConfigMapDiscoveryCacheMemory }
    }

    It 'writes keys and meta under .configmap on cache miss' {
        $dir = Join-Path $TestDrive 'miss'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
@{
    build = @{
        exec = { param([ValidateSet("Debug","Release")][string]$Configuration = "Debug") "ok" }
        description = "Build the project"
    }
    clean = { "clean" }
}
'@

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $map._sourceFile | Should -Be ([System.IO.Path]::GetFullPath($mapFile))

        $cache = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $cachePath = Join-Path $dir '.configmap\discovery.build.cache.json'
        Test-Path $cachePath | Should -BeTrue
        $cache.entries.hierarchical | Should -Not -BeNullOrEmpty

        $build = @($cache.entries.hierarchical) | Where-Object { $_.key -eq 'build' } | Select-Object -First 1
        $build | Should -Not -BeNullOrEmpty
        $build.description | Should -Be 'Build the project'
        $build.isParent | Should -BeFalse
        $params = @($build.parameters)
        $params.Count | Should -Be 1
        $params[0].name | Should -Be 'Configuration'
        $params[0].validateSet | Should -Be @('Debug', 'Release')
    }

    It 'returns the same payload on hit without rewriting when mtime is unchanged' {
        $dir = Join-Path $TestDrive 'hit'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{ build = { "ok" } }'

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $first = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $cachePath = Join-Path $dir '.configmap\discovery.build.cache.json'
        $before = Get-Item $cachePath

        Start-Sleep -Milliseconds 50
        & (Get-Module ConfigMap) { Clear-ConfigMapDiscoveryCacheMemory }

        $second = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $after = Get-Item $cachePath
        $after.LastWriteTimeUtc | Should -Be $before.LastWriteTimeUtc
        @($second.entries.hierarchical).key | Should -Be @($first.entries.hierarchical).key
    }

    It 'rebuilds when the root map mtime changes' {
        $dir = Join-Path $TestDrive 'root-mtime'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{ build = { "ok" } }'

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $null = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $cachePath = Join-Path $dir '.configmap\discovery.build.cache.json'
        $before = (Get-Item $cachePath).LastWriteTimeUtc

        Start-Sleep -Milliseconds 1100
        Set-Content -Path $mapFile -Value '@{ build = { "ok" }; clean = { "clean" } }'
        & (Get-Module ConfigMap) { Clear-ConfigMapDiscoveryCacheMemory }

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $cache = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $after = (Get-Item $cachePath).LastWriteTimeUtc
        $after | Should -BeGreaterThan $before
        @($cache.entries.hierarchical).key | Should -Contain 'clean'
    }

    It 'rebuilds when an included map mtime changes' {
        $dir = Join-Path $TestDrive 'include-mtime'
        $child = Join-Path $dir 'child'
        New-Item -ItemType Directory -Path $child -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
@{
    "#include" = @{ child = @{ prefix = $true } }
    root = { "root" }
}
'@
        $childMap = Join-Path $child '.build.map.ps1'
        Set-Content -Path $childMap -Value '@{ task = { "task" } }'

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $null = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $cachePath = Join-Path $dir '.configmap\discovery.build.cache.json'
        $before = (Get-Item $cachePath).LastWriteTimeUtc

        Start-Sleep -Milliseconds 1100
        Set-Content -Path $childMap -Value '@{ task = { "task" }; extra = { "extra" } }'
        & (Get-Module ConfigMap) { Clear-ConfigMapDiscoveryCacheMemory }

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $cache = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $after = (Get-Item $cachePath).LastWriteTimeUtc
        $after | Should -BeGreaterThan $before
        @($cache.entries.hierarchical).key | Should -Contain 'child.extra'
    }

    It 'rebuilds when a previously missing include appears' {
        $dir = Join-Path $TestDrive 'missing-include'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
@{
    "#include" = @{ child = @{ prefix = $true } }
    root = { "root" }
}
'@

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $first = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $deps = @($first.dependencies)
        $missing = $deps | Where-Object { $_.path -like '*\child\.build.map.ps1' -or $_.path -like '*/child/.build.map.ps1' } | Select-Object -First 1
        $missing | Should -Not -BeNullOrEmpty
        $missing.ticks | Should -BeNullOrEmpty

        $child = Join-Path $dir 'child'
        New-Item -ItemType Directory -Path $child -Force | Out-Null
        Set-Content -Path (Join-Path $child '.build.map.ps1') -Value '@{ task = { "task" } }'
        & (Get-Module ConfigMap) { Clear-ConfigMapDiscoveryCacheMemory }

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $second = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        @($second.entries.hierarchical).key | Should -Contain 'child.task'
    }

    It 'does not create a cache file for in-memory maps' {
        $dir = Join-Path $TestDrive 'in-memory'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $map = @{ build = { "ok" } }
        $result = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $result | Should -BeNullOrEmpty
        Test-Path (Join-Path $dir '.configmap') | Should -BeFalse
    }

    It 'feeds Get-EntryCompletion from the cache' {
        $dir = Join-Path $TestDrive 'completion'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{ alpha = { "a" }; beta = { "b" } }'

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $completions = Get-EntryCompletion $map -language build -wordToComplete 'a'
        $completions | Should -Be @('alpha')

        $cachePath = Join-Path $dir '.configmap\discovery.build.cache.json'
        Test-Path $cachePath | Should -BeTrue
    }
}
