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

        It 'runs a list of dependencies in the order written' {
            $map = [ordered]@{
                lint    = { $global:depRan.Add('lint') }
                restore = { $global:depRan.Add('restore') }
                build   = @{ _dependsOn = @('restore', 'lint'); exec = { $global:depRan.Add('build') } }
            }

            qbuild -map $map build

            $global:depRan | Should -Be @('restore', 'lint', 'build')
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

        It 'prints which dependency runs for which entry' {
            $map = @{
                restore = { }
                build   = @{ _dependsOn = 'restore'; exec = { } }
            }

            qbuild -map $map build

            Should -Invoke -ModuleName ConfigMap Write-Host -ParameterFilter { "$Object" -eq '-> restore (dependency of build)' }
        }

        It 'starts afresh on each qbuild call' {
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

    Context 'errors' {
        It 'reports a cycle with its chain' {
            $map = [ordered]@{
                a = @{ _dependsOn = 'b'; exec = { $global:depRan.Add('a') } }
                b = @{ _dependsOn = 'a'; exec = { $global:depRan.Add('b') } }
            }

            { qbuild -map $map a } | Should -Throw '*cycle*a -> b -> a*'
            $global:depRan | Should -BeNullOrEmpty
        }

        It 'reports an entry that depends on itself' {
            $map = @{
                a = @{ _dependsOn = 'a'; exec = { $global:depRan.Add('a') } }
            }

            { qbuild -map $map a } | Should -Throw '*cycle*a -> a*'
            $global:depRan | Should -BeNullOrEmpty
        }

        It 'reports an unresolved dependency and points file lists at _cacheDependsOn' {
            $map = @{
                build = @{ _dependsOn = 'helpers.ps1'; exec = { $global:depRan.Add('build') } }
            }

            { qbuild -map $map build } | Should -Throw "*'helpers.ps1'*of 'build'*not found*_cacheDependsOn*"
            $global:depRan | Should -BeNullOrEmpty
        }

        It 'checks every dependency before running any' {
            $map = [ordered]@{
                restore = { $global:depRan.Add('restore') }
                build   = @{ _dependsOn = @('restore', 'missing'); exec = { $global:depRan.Add('build') } }
            }

            { qbuild -map $map build } | Should -Throw "*'missing'*not found*"
            $global:depRan | Should -BeNullOrEmpty
        }

        It 'rejects an item that is not an entry path' {
            $map = @{
                build = @{ _dependsOn = @(@{ entry = 'restore' }); exec = { } }
            }

            { qbuild -map $map build } | Should -Throw "*_dependsOn of 'build'*entry path*"
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

        It 'does not reach the entry as an argument' {
            $map = @{
                build = { param($_context) $global:depRan.Add("build:$($_context.additionalArgs -join ' ')") }
            }

            qbuild -map $map build -NoDeps

            $global:depRan | Should -Be @('build:')
        }
    }
}

Describe 'samples/dependencies' {
    BeforeAll {
        $script:sampleMap = Join-Path $PSScriptRoot '..' 'samples' 'dependencies' '.build.map.ps1'
    }

    It 'runs pack after its prerequisites, each once' {
        $output = qbuild -map $script:sampleMap pack 6>&1 | ForEach-Object { "$_" }

        $output | Should -Be @(
            '-> lint (dependency of pack)'
            'linting'
            '-> restore (dependency of test)'
            'restoring packages'
            '-> build (dependency of test)'
            'building'
            '-> test (dependency of pack)'
            'running tests'
            '-> api.build (dependency of pack)'
            'building api'
            'packing'
        )
    }

    It 'runs only pack with -NoDeps' {
        $output = qbuild -map $script:sampleMap pack -NoDeps 6>&1 | ForEach-Object { "$_" }

        $output | Should -Be @('packing')
    }
}
