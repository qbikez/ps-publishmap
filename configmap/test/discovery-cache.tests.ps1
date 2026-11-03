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

    It 'writes discovery.configuration.cache.json for a canonical configuration map' {
        $dir = Join-Path $TestDrive 'canonical-conf'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.configuration.map.ps1'
        Set-Content -Path $mapFile -Value '@{ database = @{ get = { "ok" } } }'

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $cache = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language conf
        } $map

        $cachePath = Join-Path $dir '.configmap\discovery.configuration.cache.json'
        Test-Path $cachePath | Should -BeTrue
        $cache.language | Should -Be 'conf'
        @($cache.entries.hierarchical).key | Should -Contain 'database'
    }

    It 'writes separate cache files per language for a non-canonical map' {
        $dir = Join-Path $TestDrive 'non-canonical'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir 'foo.ps1'
        Set-Content -Path $mapFile -Value '@{ alpha = { "a" } }'

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $buildCache = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        & (Get-Module ConfigMap) { Clear-ConfigMapDiscoveryCacheMemory }

        $confCache = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language conf
        } $map

        $buildPath = Join-Path $dir '.configmap\discovery.foo.build.cache.json'
        $confPath = Join-Path $dir '.configmap\discovery.foo.conf.cache.json'
        Test-Path $buildPath | Should -BeTrue
        Test-Path $confPath | Should -BeTrue

        $buildCache.language | Should -Be 'build'
        $confCache.language | Should -Be 'conf'
        (Get-Content $buildPath -Raw | ConvertFrom-Json).language | Should -Be 'build'
        (Get-Content $confPath -Raw | ConvertFrom-Json).language | Should -Be 'conf'
        @($buildCache.entries.hierarchical).key | Should -Contain 'alpha'
        @($confCache.entries.hierarchical).key | Should -Contain 'alpha'
    }

    It 'returns live descriptors when disk cache write fails' {
        $dir = Join-Path $TestDrive 'write-fail'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $blocker = Join-Path $dir '.configmap'
        Set-Content -Path $blocker -Value 'not a directory'
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{ alpha = { "a" }; beta = { "b" } }'

        $map = Import-ConfigMap -Map $mapFile -LookUp:$false
        $cache = & (Get-Module ConfigMap) {
            param($Map)
            Get-ConfigMapDiscoveryCache -Map $Map -Language build
        } $map

        $cache | Should -Not -BeNullOrEmpty
        @($cache.entries.hierarchical).key | Should -Contain 'alpha'
        Test-Path -LiteralPath $blocker -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $dir '.configmap\discovery.build.cache.json') | Should -BeFalse
    }

    It 'writes user cache under HOME/.configmap/<project> when map sets DiscoveryCacheLocation' {
        $userHome = Join-Path $TestDrive 'user-home-map'
        New-Item -ItemType Directory -Path $userHome -Force | Out-Null
        $dir = Join-Path $TestDrive 'user-loc-map'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
@{
    _settings = @{ DiscoveryCacheLocation = 'user' }
    alpha = { "a" }
}
'@

        $previousHome = $env:HOME
        $env:HOME = $userHome
        try {
            $map = Import-ConfigMap -Map $mapFile -LookUp:$false
            $cache = & (Get-Module ConfigMap) {
                param($Map)
                Get-ConfigMapDiscoveryCache -Map $Map -Language build
            } $map

            $project = & (Get-Module ConfigMap) {
                param($SourceFile)
                ConvertTo-ConfigMapDiscoveryCacheProjectName -SourceFile $SourceFile
            } $mapFile
            $expected = Join-Path $userHome ".configmap\$project\discovery.build.cache.json"

            $cache | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $expected | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $dir '.configmap') | Should -BeFalse

            $info = & (Get-Module ConfigMap) {
                param($Map)
                Get-ConfigMapDiscoveryCacheInfo -Map $Map -Language build
            } $map
            $info.Location | Should -Be 'user'
            $info.Path | Should -Be ([System.IO.Path]::GetFullPath($expected))
        }
        finally {
            if ($null -eq $previousHome) {
                Remove-Item env:HOME -ErrorAction SilentlyContinue
            }
            else {
                $env:HOME = $previousHome
            }
        }
    }

    It 'writes user cache when QCONF_DiscoveryCacheLocation is user' {
        $userHome = Join-Path $TestDrive 'user-home-env'
        New-Item -ItemType Directory -Path $userHome -Force | Out-Null
        $dir = Join-Path $TestDrive 'user-loc-env'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{ alpha = { "a" } }'

        $previousHome = $env:HOME
        $previousLocation = $env:QCONF_DiscoveryCacheLocation
        $env:HOME = $userHome
        $env:QCONF_DiscoveryCacheLocation = 'user'
        try {
            & (Get-Module ConfigMap) { Update-ConfigMapSettings | Out-Null }

            $map = Import-ConfigMap -Map $mapFile -LookUp:$false
            $null = & (Get-Module ConfigMap) {
                param($Map)
                Get-ConfigMapDiscoveryCache -Map $Map -Language build
            } $map

            $project = & (Get-Module ConfigMap) {
                param($SourceFile)
                ConvertTo-ConfigMapDiscoveryCacheProjectName -SourceFile $SourceFile
            } $mapFile
            Test-Path -LiteralPath (Join-Path $userHome ".configmap\$project\discovery.build.cache.json") | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $dir '.configmap') | Should -BeFalse
        }
        finally {
            if ($null -eq $previousHome) {
                Remove-Item env:HOME -ErrorAction SilentlyContinue
            }
            else {
                $env:HOME = $previousHome
            }
            if ($null -eq $previousLocation) {
                Remove-Item env:QCONF_DiscoveryCacheLocation -ErrorAction SilentlyContinue
            }
            else {
                $env:QCONF_DiscoveryCacheLocation = $previousLocation
            }
            & (Get-Module ConfigMap) { Update-ConfigMapSettings | Out-Null }
        }
    }

    It 'uses a Cursor-style sanitized project folder for user cache' {
        $sourceFile = Join-Path 'C:\git\hmdev\demo' '.build.map.ps1'
        $name = & (Get-Module ConfigMap) {
            param($SourceFile)
            ConvertTo-ConfigMapDiscoveryCacheProjectName -SourceFile $SourceFile
        } $sourceFile

        $name | Should -Be 'C-git-hmdev-demo'
    }

    It 'finds a user cache while the write location is local without reading map settings' {
        $userHome = Join-Path $TestDrive 'user-home-probe'
        New-Item -ItemType Directory -Path $userHome -Force | Out-Null
        $dir = Join-Path $TestDrive 'user-loc-probe'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
@{
    _settings = @{ DiscoveryCacheLocation = 'user' }
    alpha = { "a" }
}
'@

        $previousHome = $env:HOME
        $env:HOME = $userHome
        try {
            $map = Import-ConfigMap -Map $mapFile -LookUp:$false
            $null = & (Get-Module ConfigMap) {
                param($Map)
                Get-ConfigMapDiscoveryCache -Map $Map -Language build
            } $map

            $project = & (Get-Module ConfigMap) {
                param($SourceFile)
                ConvertTo-ConfigMapDiscoveryCacheProjectName -SourceFile $SourceFile
            } $mapFile
            $userPath = Join-Path $userHome ".configmap\$project\discovery.build.cache.json"
            Test-Path $userPath | Should -BeTrue

            & (Get-Module ConfigMap) { Clear-ConfigMapDiscoveryCacheMemory }
            $map.Remove('_settings')

            $before = (Get-Item -LiteralPath $userPath).LastWriteTimeUtc
            $cache = & (Get-Module ConfigMap) {
                param($Map)
                Get-ConfigMapDiscoveryCache -Map $Map -Language build
            } $map

            $cache | Should -Not -BeNullOrEmpty
            @($cache.entries.hierarchical).key | Should -Contain 'alpha'
            (Get-Item -LiteralPath $userPath).LastWriteTimeUtc | Should -Be $before
            Test-Path -LiteralPath (Join-Path $dir '.configmap') | Should -BeFalse
        }
        finally {
            if ($null -eq $previousHome) {
                Remove-Item env:HOME -ErrorAction SilentlyContinue
            }
            else {
                $env:HOME = $previousHome
            }
        }
    }

    It 'finds a local cache while the write location is user' {
        $userHome = Join-Path $TestDrive 'user-home-local-hit'
        New-Item -ItemType Directory -Path $userHome -Force | Out-Null
        $dir = Join-Path $TestDrive 'local-hit-user-write'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{ alpha = { "a" } }'

        $previousHome = $env:HOME
        $env:HOME = $userHome
        try {
            $map = Import-ConfigMap -Map $mapFile -LookUp:$false
            $null = & (Get-Module ConfigMap) {
                param($Map)
                Get-ConfigMapDiscoveryCache -Map $Map -Language build
            } $map
            $localPath = Join-Path $dir '.configmap\discovery.build.cache.json'
            Test-Path $localPath | Should -BeTrue

            & (Get-Module ConfigMap) { Clear-ConfigMapDiscoveryCacheMemory }
            $map._settings = @{ DiscoveryCacheLocation = 'user' }

            $before = (Get-Item -LiteralPath $localPath).LastWriteTimeUtc
            $cache = & (Get-Module ConfigMap) {
                param($Map)
                Get-ConfigMapDiscoveryCache -Map $Map -Language build
            } $map

            $project = & (Get-Module ConfigMap) {
                param($SourceFile)
                ConvertTo-ConfigMapDiscoveryCacheProjectName -SourceFile $SourceFile
            } $mapFile
            $userPath = Join-Path $userHome ".configmap\$project\discovery.build.cache.json"

            $cache | Should -Not -BeNullOrEmpty
            @($cache.entries.hierarchical).key | Should -Contain 'alpha'
            (Get-Item -LiteralPath $localPath).LastWriteTimeUtc | Should -Be $before
            Test-Path $userPath | Should -BeFalse
        }
        finally {
            if ($null -eq $previousHome) {
                Remove-Item env:HOME -ErrorAction SilentlyContinue
            }
            else {
                $env:HOME = $previousHome
            }
        }
    }

    It 'clears both local and user cache files' {
        $userHome = Join-Path $TestDrive 'user-home-clear'
        New-Item -ItemType Directory -Path $userHome -Force | Out-Null
        $dir = Join-Path $TestDrive 'user-loc-clear'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{ alpha = { "a" } }'

        $previousHome = $env:HOME
        $env:HOME = $userHome
        try {
            $map = Import-ConfigMap -Map $mapFile -LookUp:$false
            $null = & (Get-Module ConfigMap) {
                param($Map)
                Get-ConfigMapDiscoveryCache -Map $Map -Language build
            } $map
            $localPath = Join-Path $dir '.configmap\discovery.build.cache.json'
            Test-Path $localPath | Should -BeTrue

            $userPath = & (Get-Module ConfigMap) {
                param($SourceFile)
                (Get-ConfigMapDiscoveryCacheCandidate -SourceFile $SourceFile -Language build -Location user).Path
            } $mapFile
            New-Item -ItemType Directory -Path (Split-Path -Parent $userPath) -Force | Out-Null
            Copy-Item -LiteralPath $localPath -Destination $userPath

            $null = & (Get-Module ConfigMap) {
                param($Map)
                Clear-ConfigMapDiscoveryCache -Map $Map -Language build
            } $map

            Test-Path $userPath | Should -BeFalse
            Test-Path $localPath | Should -BeFalse
        }
        finally {
            if ($null -eq $previousHome) {
                Remove-Item env:HOME -ErrorAction SilentlyContinue
            }
            else {
                $env:HOME = $previousHome
            }
        }
    }
}
