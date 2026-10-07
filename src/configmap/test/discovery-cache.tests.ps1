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

    It 'skips cache when map _settings disable DiscoveryCache' {
        $dir = Join-Path $TestDrive 'opt-out-map'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
@{
    _settings = @{ DiscoveryCache = $false }
    alpha = { "a" }
    beta = { "b" }
}
'@

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $cache = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $cache | Should -BeNullOrEmpty
        Test-Path (Join-Path $dir '.configmap') | Should -BeFalse

        $completions = Get-EntryCompletion $map -language build -wordToComplete 'a'
        $completions | Should -Be @('alpha')
        Test-Path (Join-Path $dir '.configmap') | Should -BeFalse
    }

    It 'skips cache when QCONF_DiscoveryCache is disabled' {
        $dir = Join-Path $TestDrive 'opt-out-env'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{ alpha = { "a" }; beta = { "b" } }'

        $previous = $env:QCONF_DiscoveryCache
        $env:QCONF_DiscoveryCache = '0'
        try {
            & (Get-Module ConfigMap) { Update-ConfigMapSettings | Out-Null }

            $map = Import-ConfigMap -Map $mapFile -LookUp:$false
            $cache = & (Get-Module ConfigMap) {
                param($Map)
                Get-ConfigMapDiscoveryCache -Map $Map -Language build
            } $map

            $cache | Should -BeNullOrEmpty
            Test-Path (Join-Path $dir '.configmap') | Should -BeFalse

            $completions = Get-EntryCompletion $map -language build -wordToComplete 'b'
            $completions | Should -Be @('beta')
            Test-Path (Join-Path $dir '.configmap') | Should -BeFalse
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

    It 'rebuilds when a root _dependsOn file mtime changes' {
        $dir = Join-Path $TestDrive 'depends-on-mtime'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $dataFile = Join-Path $dir 'data.txt'
        Set-Content -Path $dataFile -Value 'alpha'
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
$data = (Get-Content (Join-Path $PSScriptRoot 'data.txt') -Raw).Trim()
@{
    _dependsOn = @('data.txt')
    "$data"    = { "ok" }
}
'@

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $first = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        @($first.entries.hierarchical).key | Should -Contain 'alpha'

        $cachePath = Join-Path $dir '.configmap\discovery.build.cache.json'
        $before = (Get-Item $cachePath).LastWriteTimeUtc

        Start-Sleep -Milliseconds 1100
        Set-Content -Path $dataFile -Value 'beta'
        & (Get-Module ConfigMap) { Clear-ConfigMapDiscoveryCacheMemory }

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $second = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $after = (Get-Item $cachePath).LastWriteTimeUtc
        $after | Should -BeGreaterThan $before
        @($second.entries.hierarchical).key | Should -Contain 'beta'
        @($second.entries.hierarchical).key | Should -Not -Contain 'alpha'
    }

    It 'rebuilds when a previously missing _dependsOn file appears' {
        $dir = Join-Path $TestDrive 'depends-on-missing'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
@{
    _dependsOn = @('sidecar.txt')
    root       = { "root" }
}
'@

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $first = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $sidecar = [System.IO.Path]::GetFullPath((Join-Path $dir 'sidecar.txt'))
        $missing = @($first.dependencies) | Where-Object { $_.path -eq $sidecar } | Select-Object -First 1
        $missing | Should -Not -BeNullOrEmpty
        $missing.ticks | Should -BeNullOrEmpty

        Set-Content -Path $sidecar -Value 'created'
        & (Get-Module ConfigMap) { Clear-ConfigMapDiscoveryCacheMemory }

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $second = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $found = @($second.dependencies) | Where-Object { $_.path -eq $sidecar } | Select-Object -First 1
        $found.ticks | Should -Not -BeNullOrEmpty
    }

    It 'records _dependsOn on a leaf target in cache dependencies' {
        $dir = Join-Path $TestDrive 'depends-on-leaf'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $leafDep = Join-Path $dir 'leaf-dep.txt'
        Set-Content -Path $leafDep -Value 'dep'
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
@{
    build = @{
        exec       = { "ok" }
        _dependsOn = @('leaf-dep.txt')
    }
}
'@

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $cache = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $expected = [System.IO.Path]::GetFullPath($leafDep)
        @($cache.dependencies).path | Should -Contain $expected
    }

    It 'resolves a relative _dependsOn path against the map directory' {
        $dir = Join-Path $TestDrive 'depends-on-relative'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $extra = Join-Path $dir 'extra.txt'
        Set-Content -Path $extra -Value 'extra'
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
@{
    _dependsOn = 'extra.txt'
    build      = { "ok" }
}
'@

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $cache = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $expected = [System.IO.Path]::GetFullPath($extra)
        @($cache.dependencies).path | Should -Contain $expected
    }

    It 'does not expose _dependsOn as a completion key' {
        $dir = Join-Path $TestDrive 'depends-on-completion'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
@{
    _dependsOn = @('extra.txt')
    alpha      = { "a" }
}
'@

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $completions = @(Get-EntryCompletion $map -language build -wordToComplete '')
        $completions | Should -Contain 'alpha'
        $completions | Should -Not -Contain '_dependsOn'

        $underscore = @(Get-EntryCompletion $map -language build -wordToComplete '_')
        $underscore | Should -Not -Contain '_dependsOn'
    }
}
