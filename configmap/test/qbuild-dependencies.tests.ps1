BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1
}

Describe 'qbuild _dependsOn' {
    BeforeEach {
        $global:depRan = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName ConfigMap Write-Host { }
    }
    AfterEach {
        Remove-Variable -Name depRan -Scope Global -ErrorAction SilentlyContinue
        $global:LASTEXITCODE = 0
    }

    Context 'ordering' {
        It 'runs a dependency before the entry' {
            $map = @{
                restore = { $global:depRan.Add('restore') }
                build   = @{
                    _dependsOn = 'restore'
                    exec       = { $global:depRan.Add('build') }
                }
            }

            qbuild -map $map build

            $global:depRan | Should -Be @('restore', 'build')
        }

        It 'runs transitive dependencies depth-first' {
            $map = [ordered]@{
                restore = { $global:depRan.Add('restore') }
                build   = @{ _dependsOn = 'restore'; exec = { $global:depRan.Add('build') } }
                test    = @{ _dependsOn = 'build'; exec = { $global:depRan.Add('test') } }
            }

            qbuild -map $map test

            $global:depRan | Should -Be @('restore', 'build', 'test')
        }

        It 'runs a shared dependency of a diamond once' {
            $map = [ordered]@{
                restore = { $global:depRan.Add('restore') }
                ui      = @{ _dependsOn = 'restore'; exec = { $global:depRan.Add('ui') } }
                api     = @{ _dependsOn = 'restore'; exec = { $global:depRan.Add('api') } }
                build   = @{ _dependsOn = @('ui', 'api'); exec = { $global:depRan.Add('build') } }
            }

            qbuild -map $map build

            $global:depRan | Should -Be @('restore', 'ui', 'api', 'build')
        }

        It 'prints which dependency runs for which entry' {
            $map = @{
                restore = { }
                build   = @{ _dependsOn = 'restore'; exec = { } }
            }

            qbuild -map $map build

            Should -Invoke -ModuleName ConfigMap Write-Host -ParameterFilter { "$Object" -match "restore.*dependency of build" }
        }
    }

    Context 'run once per qbuild call' {
        It 'runs a dependency shared by two requested entries once' {
            $map = [ordered]@{
                restore = { $global:depRan.Add('restore') }
                build   = @{ _dependsOn = 'restore'; exec = { $global:depRan.Add('build') } }
                test    = @{ _dependsOn = 'restore'; exec = { $global:depRan.Add('test') } }
            }

            qbuild -map $map build, test

            $global:depRan | Should -Be @('restore', 'build', 'test')
        }

        It 'does not rerun a dependency that was requested earlier in the same call' {
            $map = [ordered]@{
                build = { $global:depRan.Add('build') }
                test  = @{ _dependsOn = 'build'; exec = { $global:depRan.Add('test') } }
            }

            qbuild -map $map build, test

            $global:depRan | Should -Be @('build', 'test')
        }

        It 'does not rerun a requested entry that already ran as a dependency' {
            $map = [ordered]@{
                build = { $global:depRan.Add('build') }
                test  = @{ _dependsOn = 'build'; exec = { $global:depRan.Add('test') } }
            }

            qbuild -map $map test, build

            $global:depRan | Should -Be @('build', 'test')
        }

        It 'still runs an entry requested twice when no dependency is involved' {
            $map = @{ build = { $global:depRan.Add('build') } }

            qbuild -map $map build, build

            $global:depRan | Should -Be @('build', 'build')
        }

        It 'runs the same dependency again for different args' {
            $map = [ordered]@{
                build = { param($Configuration = 'Debug') $global:depRan.Add("build:$Configuration") }
                pack  = @{
                    _dependsOn = @('build', @{ entry = 'build'; args = @{ Configuration = 'Release' } })
                    exec       = { $global:depRan.Add('pack') }
                }
            }

            qbuild -map $map pack

            $global:depRan | Should -Be @('build:Debug', 'build:Release', 'pack')
        }

        It 'starts a fresh run-once set for each qbuild call' {
            $map = @{
                restore = { $global:depRan.Add('restore') }
                build   = @{ _dependsOn = 'restore'; exec = { $global:depRan.Add('build') } }
            }

            qbuild -map $map build
            qbuild -map $map build

            $global:depRan | Should -Be @('restore', 'build', 'restore', 'build')
        }
    }

    Context 'arguments' {
        It 'passes declared args only to the dependency' {
            $map = [ordered]@{
                build = { param($Configuration = 'Debug') $global:depRan.Add("build:$Configuration") }
                test  = @{
                    _dependsOn = @(@{ entry = 'build'; args = @{ Configuration = 'Release' } })
                    exec       = { param($Filter) $global:depRan.Add("test:$Filter") }
                }
            }

            qbuild -map $map test -Filter unit

            $global:depRan | Should -Be @('build:Release', 'test:unit')
        }

        It 'does not pass the caller''s args to a dependency with the same parameter' {
            $map = [ordered]@{
                build = { param($Configuration = 'Debug') $global:depRan.Add("build:$Configuration") }
                test  = @{
                    _dependsOn = 'build'
                    exec       = { param($Configuration = 'Debug') $global:depRan.Add("test:$Configuration") }
                }
            }

            qbuild -map $map test -Configuration Release

            $global:depRan | Should -Be @('build:Debug', 'test:Release')
        }

        It 'does not pass passthrough args to a dependency' {
            $map = [ordered]@{
                build = { param($_context) $global:depRan.Add("build:$($_context.additionalArgs -join ' ')") }
                test  = @{
                    _dependsOn = 'build'
                    exec       = { param($_context) $global:depRan.Add("test:$($_context.additionalArgs -join ' ')") }
                }
            }

            qbuild -map $map test -- --verbose

            $global:depRan | Should -Be @('build:', 'test:--verbose')
        }
    }

    Context 'name resolution' {
        It 'resolves a dotted path from the map root' {
            $map = [ordered]@{
                api = [ordered]@{
                    build = { $global:depRan.Add('api.build') }
                }
                ui  = [ordered]@{
                    build = @{ _dependsOn = 'api.build'; exec = { $global:depRan.Add('ui.build') } }
                }
            }

            qbuild -map $map ui.build

            $global:depRan | Should -Be @('api.build', 'ui.build')
        }

        It 'resolves ./name to a sibling in the same group' {
            $map = [ordered]@{
                build = { $global:depRan.Add('build') }
                api   = [ordered]@{
                    build = { $global:depRan.Add('api.build') }
                    test  = @{ _dependsOn = './build'; exec = { $global:depRan.Add('api.test') } }
                }
            }

            qbuild -map $map api.test

            $global:depRan | Should -Be @('api.build', 'api.test')
        }

        It 'treats ./name and its full path as the same dependency' {
            $map = [ordered]@{
                api = [ordered]@{
                    build = { $global:depRan.Add('api.build') }
                    lint  = @{ _dependsOn = './build'; exec = { $global:depRan.Add('api.lint') } }
                    test  = @{ _dependsOn = @('api.build', 'api.lint'); exec = { $global:depRan.Add('api.test') } }
                }
            }

            qbuild -map $map api.test

            $global:depRan | Should -Be @('api.build', 'api.lint', 'api.test')
        }

        It 'rejects ../ references' {
            $map = [ordered]@{
                api = [ordered]@{
                    test = @{ _dependsOn = '../build'; exec = { } }
                }
            }

            { qbuild -map $map api.test } | Should -Throw "*'../build'*not supported*"
        }
    }

    Context 'errors' {
        It 'reports a cycle with its chain' {
            $map = [ordered]@{
                a = @{ _dependsOn = 'b'; exec = { $global:depRan.Add('a') } }
                b = @{ _dependsOn = 'a'; exec = { $global:depRan.Add('b') } }
            }

            { qbuild -map $map a } | Should -Throw '*cycle*a -> b -> a*'
            $global:depRan | Should -BeNullOrEmpty
        }

        It 'reports an unresolved dependency and points file lists at _cacheDependsOn' {
            $map = @{
                build = @{ _dependsOn = 'helpers.ps1'; exec = { $global:depRan.Add('build') } }
            }

            { qbuild -map $map build } | Should -Throw "*'helpers.ps1'*not found*_cacheDependsOn*"
            $global:depRan | Should -BeNullOrEmpty
        }

        It 'rejects a dependency on a group without exec and suggests .all' {
            $map = [ordered]@{
                api   = [ordered]@{ build = { } }
                build = @{ _dependsOn = 'api'; exec = { } }
            }

            { qbuild -map $map build } | Should -Throw "*'api'*group*'api.all'*"
        }

        It 'rejects a malformed dependency item' {
            $map = @{
                build = @{ _dependsOn = @(@{ args = @{} }); exec = { } }
            }

            { qbuild -map $map build } | Should -Throw '*_dependsOn*entry*'
        }
    }

    Context 'failures' {
        It 'stops before the entry when a dependency throws' {
            $map = @{
                restore = { throw 'restore broke' }
                build   = @{ _dependsOn = 'restore'; exec = { $global:depRan.Add('build') } }
            }

            { qbuild -map $map build } | Should -Throw '*restore broke*'
            $global:depRan | Should -BeNullOrEmpty
        }

        It 'stops before the entry when a dependency exits non-zero' {
            $map = @{
                restore = { $global:LASTEXITCODE = 3 }
                build   = @{ _dependsOn = 'restore'; exec = { $global:depRan.Add('build') } }
            }

            { qbuild -map $map build } | Should -Throw "*Dependency 'restore' of 'build' failed with exit code 3*"
            $global:depRan | Should -BeNullOrEmpty
        }

        It 'ignores a stale non-zero exit code from before the dependency ran' {
            $map = @{
                restore = { $global:depRan.Add('restore') }
                build   = @{ _dependsOn = 'restore'; exec = { $global:depRan.Add('build') } }
            }
            $global:LASTEXITCODE = 7

            qbuild -map $map build

            $global:depRan | Should -Be @('restore', 'build')
        }
    }

    Context '-NoDeps' {
        It 'runs only the requested entry' {
            $map = @{
                restore = { $global:depRan.Add('restore') }
                build   = @{ _dependsOn = 'restore'; exec = { $global:depRan.Add('build') } }
            }

            qbuild -map $map build -NoDeps

            $global:depRan | Should -Be @('build')
        }

        It 'does not reach the entry as a parameter' {
            $map = @{
                build = { param($_context) $global:depRan.Add("build:$($_context.additionalArgs -join ' ')") }
            }

            qbuild -map $map build -NoDeps

            $global:depRan | Should -Be @('build:')
        }
    }

    Context 'groups' {
        It 'does not apply a group''s _dependsOn to a child run on its own' {
            $map = [ordered]@{
                restore = { $global:depRan.Add('restore') }
                api     = [ordered]@{
                    _dependsOn = 'restore'
                    build      = { $global:depRan.Add('api.build') }
                }
            }

            qbuild -map $map api.build

            $global:depRan | Should -Be @('api.build')
        }

        It 'runs the group''s and children''s dependencies before group.all' {
            $map = [ordered]@{
                restore = { $global:depRan.Add('restore') }
                gen     = { $global:depRan.Add('gen') }
                api     = [ordered]@{
                    _dependsOn = 'restore'
                    build      = @{ _dependsOn = 'gen'; exec = { $global:depRan.Add('api.build') } }
                    test       = { $global:depRan.Add('api.test') }
                }
            }

            qbuild -map $map api.all

            $global:depRan | Should -Be @('restore', 'gen', 'api.build', 'api.test')
        }

        It 'runs the children of a group.all dependency' {
            $map = [ordered]@{
                api  = [ordered]@{
                    build = { $global:depRan.Add('api.build') }
                    test  = { $global:depRan.Add('api.test') }
                }
                ship = @{ _dependsOn = 'api.all'; exec = { $global:depRan.Add('ship') } }
            }

            qbuild -map $map ship

            $global:depRan | Should -Be @('api.build', 'api.test', 'ship')
        }
    }

    Context 'process types' {
        BeforeEach {
            $script:workDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $script:workDir | Out-Null
            Push-Location $script:workDir
        }
        AfterEach {
            Pop-Location
        }

        It 'runs a steps process as a dependency through its own handler' {
            $mapFile = Join-Path $script:workDir '.build.map.ps1'
            Set-Content -Path $mapFile -Value @'
[ordered]@{
    bootstrap = [ordered]@{
        _settings = @{ process = 'steps' }
        restore   = { $global:depRan.Add('bootstrap.restore') }
        seed      = { $global:depRan.Add('bootstrap.seed') }
    }
    dev = @{
        _dependsOn = 'bootstrap'
        exec       = { $global:depRan.Add('dev') }
    }
}
'@

            qbuild -map $mapFile dev

            $global:depRan | Should -Be @('bootstrap.restore', 'bootstrap.seed', 'dev')
        }

        It 'runs the dependencies a steps process declares' {
            $mapFile = Join-Path $script:workDir '.build.map.ps1'
            Set-Content -Path $mapFile -Value @'
[ordered]@{
    restore = { $global:depRan.Add('restore') }
    bootstrap = [ordered]@{
        _settings  = @{ process = 'steps' }
        _dependsOn = 'restore'
        seed       = { $global:depRan.Add('bootstrap.seed') }
    }
}
'@

            qbuild -map $mapFile bootstrap

            $global:depRan | Should -Be @('restore', 'bootstrap.seed')
            $state = Get-Content (Join-Path $script:workDir '.configmap/process/bootstrap.state.json') -Raw | ConvertFrom-Json -AsHashtable
            $state.steps.Keys | Should -Not -Contain '_dependsOn'
        }

        It 'sets an options preset as a dependency using ProcessAction and ProcessValue args' {
            $mapFile = Join-Path $script:workDir '.build.map.ps1'
            Set-Content -Path $mapFile -Value @'
[ordered]@{
    env = [ordered]@{
        _settings = @{ process = 'options' }
        options   = [ordered]@{
            local = @{ name = 'local' }
            prod  = @{ name = 'prod' }
        }
        get       = { param($ctx, $options) 'local' }
        set       = { param($ctx, $key, $value) $global:depRan.Add("env:$key") }
    }
    deploy = @{
        _dependsOn = @(@{ entry = 'env'; args = @{ ProcessAction = 'set'; ProcessValue = 'prod' } })
        exec       = { $global:depRan.Add('deploy') }
    }
}
'@

            qbuild -map $mapFile deploy

            $global:depRan | Should -Be @('env:prod', 'deploy')
        }
    }

    Context 'map structure' {
        It 'does not treat _dependsOn as a child entry' {
            $map = [ordered]@{
                restore = { $global:depRan.Add('restore') }
                api     = [ordered]@{
                    _dependsOn = 'restore'
                    build      = { $global:depRan.Add('api.build') }
                }
            }

            $children = InModuleScope ConfigMap -Parameters @{ Map = $map } {
                param($Map)
                Get-BuildAllChildren -ParentEntry $Map.api -Language build -ParentKey 'api'
            }

            @($children.Keys) | Should -Be @('api.build')
        }
    }
}

Describe 'qbuild list and !describe show _dependsOn' {
    It 'lists the dependencies of an in-memory map entry' {
        $map = [ordered]@{
            restore = { }
            build   = @{
                description = 'Build it'
                _dependsOn  = @('restore', @{ entry = 'restore'; args = @{ Force = $true } })
                exec        = { }
            }
        }

        $output = qbuild -map $map list 6>&1 | Out-String

        $output | Should -Match 'build\s+Build it\s+\(needs: restore, restore -Force:True\)'
        $output | Should -Not -Match 'restore\s+.*needs'
    }

    It 'lists the dependencies of a file map entry from the discovery cache' {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $dir | Out-Null
        $mapFile = Join-Path $dir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
[ordered]@{
    restore = { }
    build   = @{ _dependsOn = 'restore'; exec = { } }
}
'@

        $first = qbuild -map $mapFile list 6>&1 | Out-String
        $second = qbuild -map $mapFile list 6>&1 | Out-String

        $first | Should -Match 'build\s+\(needs: restore\)'
        $second | Should -Match 'build\s+\(needs: restore\)'
        $cache = Get-Content (Join-Path $dir '.configmap/discovery.build.cache.json') -Raw | ConvertFrom-Json
        @($cache.entries.hierarchical | Where-Object key -eq 'build').dependsOn | Should -Be @('restore')
    }

    It 'includes dependencies in the command catalog' {
        $map = [ordered]@{
            restore = { }
            build   = @{ _dependsOn = 'restore'; exec = { } }
        }

        $catalog = Get-ConfigMapCommandCatalog -Map $map
        ($catalog | Where-Object Name -eq 'build').DependsOn | Should -Be @('restore')
        ($catalog | Where-Object Name -eq 'restore').DependsOn | Should -BeNullOrEmpty
    }
}

Describe 'qbuild _dependsOn with the concurrently plugin' {
    BeforeEach {
        $global:depRan = [System.Collections.Generic.List[string]]::new()
        $script:workDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:workDir | Out-Null
    }
    AfterEach {
        Remove-Variable -Name depRan -Scope Global -ErrorAction SilentlyContinue
        InModuleScope ConfigMap { $script:ConfigMapConcurrentlyInvoker = $null }
    }

    It 'runs dependencies once in the parent and starts children with -NoDeps' {
        $mapFile = Join-Path $script:workDir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
[ordered]@{
    restore = { $global:depRan.Add('restore') }
    dev     = [ordered]@{
        _settings = @{ Concurrently = $true }
        ui        = @{ _dependsOn = 'restore'; exec = { npm run dev } }
        api       = @{ _dependsOn = 'restore'; exec = { dotnet watch run } }
    }
}
'@

        InModuleScope ConfigMap -Parameters @{ MapFile = $mapFile } {
            param($MapFile)
            $script:capturedCommands = $null
            $script:ConfigMapConcurrentlyInvoker = {
                param($Commands)
                $script:capturedCommands = $Commands
            }
            Mock Test-ConcurrentlyAvailable { $true }
            Mock Get-TmuxInfo { $null }
            Mock Write-Host { }

            qbuild -map $MapFile dev.all

            $global:depRan | Should -Be @('restore')
            @($script:capturedCommands.Values) | Should -HaveCount 2
            foreach ($commandLine in $script:capturedCommands.Values) {
                $commandLine | Should -Match ' -NoDeps\b'
            }
        }
    }

    It 'leaves child commands unchanged when no target declares dependencies' {
        $mapFile = Join-Path $script:workDir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
[ordered]@{
    dev = [ordered]@{
        _settings = @{ Concurrently = $true }
        ui        = { npm run dev }
        api       = { dotnet watch run }
    }
}
'@

        InModuleScope ConfigMap -Parameters @{ MapFile = $mapFile } {
            param($MapFile)
            $script:capturedCommands = $null
            $script:ConfigMapConcurrentlyInvoker = {
                param($Commands)
                $script:capturedCommands = $Commands
            }
            Mock Test-ConcurrentlyAvailable { $true }
            Mock Get-TmuxInfo { $null }

            qbuild -map $MapFile dev.all

            foreach ($commandLine in $script:capturedCommands.Values) {
                $commandLine | Should -Not -Match 'NoDeps'
            }
        }
    }
}

Describe 'qbuild _dependsOn with the tmux plugin' {
    BeforeEach {
        $global:depRan = [System.Collections.Generic.List[string]]::new()
        $script:workDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:workDir | Out-Null
    }
    AfterEach {
        Remove-Variable -Name depRan -Scope Global -ErrorAction SilentlyContinue
    }

    It 'runs dependencies in place and sends only the entry, with -NoDeps, to a window' {
        $mapFile = Join-Path $script:workDir '.build.map.ps1'
        Set-Content -Path $mapFile -Value @'
[ordered]@{
    _settings = @{ TmuxAutoWindow = $true }
    restore   = { $global:depRan.Add('restore') }
    build     = @{ _dependsOn = 'restore'; exec = { $global:depRan.Add('build') } }
}
'@

        InModuleScope ConfigMap -Parameters @{ MapFile = $mapFile } {
            param($MapFile)
            Mock Get-TmuxInfo { @{ sessionName = 'dev'; windowName = 'shell' } }
            Mock Invoke-TmuxCommand { }
            Mock Write-Host { }

            qbuild -map $MapFile build

            $global:depRan | Should -Be @('restore')
            Should -Invoke Invoke-TmuxCommand -Exactly 1
            Should -Invoke Invoke-TmuxCommand -Exactly 1 -ParameterFilter { $Window -eq 'build' -and $Command -match ' -NoDeps\b' }
        }
    }
}
