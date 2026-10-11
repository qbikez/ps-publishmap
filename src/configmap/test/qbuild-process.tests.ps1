BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force
}

Describe 'qbuild process=qrun forwarding' {
    BeforeEach {
        $script:workDir = Join-Path $TestDrive ("qbuild-process-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:workDir -Force | Out-Null
        Push-Location $script:workDir

        $script:map = [ordered]@{
            build = {
                param(
                    [ValidateSet('Debug', 'Release')]
                    [string]$Configuration = 'Debug'
                )
                "built:$Configuration" | Set-Content 'build.txt'
            }

            bootstrap = [ordered]@{
                process     = 'qrun'
                description = 'test process'
                prepare     = {
                    New-Item -ItemType Directory -Path 'marker-a' -Force | Out-Null
                    'a' | Set-Content (Join-Path 'marker-a' 'done.txt')
                }
                restore     = {
                    param(
                        [ValidateSet('dev', 'prod')]
                        [string]$Environment = 'dev'
                    )
                    if (!(Test-Path 'marker-a/done.txt')) { throw 'prepare missing' }
                    "restored:$Environment" | Set-Content 'marker-b.txt'
                }
                verify      = {
                    'c' | Set-Content 'marker-c.txt'
                }
            }
        }
    }

    AfterEach {
        Pop-Location
    }

    It 'still runs default qbuild entries' {
        qbuild -map $script:map build -Configuration Release
        Get-Content 'build.txt' -Raw | Should -Match 'built:Release'
    }

    It 'forwards full process run and persists success state' {
        qbuild -map $script:map bootstrap

        Test-Path 'marker-a/done.txt' | Should -BeTrue
        Test-Path 'marker-b.txt' | Should -BeTrue
        Test-Path 'marker-c.txt' | Should -BeTrue

        $stateFiles = @(Get-ChildItem -Path (Join-Path $script:workDir '.configmap' 'process') -Recurse -Filter '*.state.json')
        $stateFiles.Count | Should -Be 1
        $state = Get-Content $stateFiles[0].FullName -Raw | ConvertFrom-Json
        $state.steps.prepare.status | Should -Be 'Succeeded'
        $state.steps.restore.status | Should -Be 'Succeeded'
        $state.steps.verify.status | Should -Be 'Succeeded'
    }

    It 'skips already succeeded steps on re-run' {
        qbuild -map $script:map bootstrap
        Remove-Item 'marker-b.txt', 'marker-c.txt' -Force

        qbuild -map $script:map bootstrap

        Test-Path 'marker-b.txt' | Should -BeFalse
        Test-Path 'marker-c.txt' | Should -BeFalse
        Test-Path 'marker-a/done.txt' | Should -BeTrue
    }

    It 'reruns succeeded steps when -Force is specified' {
        qbuild -map $script:map bootstrap
        Remove-Item 'marker-b.txt' -Force

        qbuild -map $script:map bootstrap -Force

        Test-Path 'marker-b.txt' | Should -BeTrue
        Test-Path 'marker-c.txt' | Should -BeTrue
    }

    It 'runs a single step via process.step path' {
        qbuild -map $script:map bootstrap.prepare
        Test-Path 'marker-a/done.txt' | Should -BeTrue
        Test-Path 'marker-b.txt' | Should -BeFalse

        qbuild -map $script:map bootstrap.restore
        Test-Path 'marker-b.txt' | Should -BeTrue
        Test-Path 'marker-c.txt' | Should -BeFalse
    }

    It 'runs from a step onward with -Follow' {
        qbuild -map $script:map bootstrap.prepare

        qbuild -map $script:map bootstrap.restore -Follow

        Test-Path 'marker-b.txt' | Should -BeTrue
        Test-Path 'marker-c.txt' | Should -BeTrue
    }

    It 'rejects -Follow without a step path' {
        { qbuild -map $script:map bootstrap -Follow } | Should -Throw '*-Follow requires a step path*'
    }

    It 'blocks starting mid-process when prior steps are incomplete' {
        { qbuild -map $script:map bootstrap.restore } | Should -Throw '*prior steps are incomplete*'
        Test-Path 'marker-b.txt' | Should -BeFalse
    }

    It 'allows skipping incomplete prior steps with -Force' {
        $indep = [ordered]@{
            setup = [ordered]@{
                process = 'qrun'
                a       = { 'a' | Set-Content 'a.txt' }
                b       = { 'b' | Set-Content 'b.txt' }
                c       = { 'c' | Set-Content 'c.txt' }
            }
        }

        qbuild -map $indep setup.b -Force
        Test-Path 'b.txt' | Should -BeTrue
        Test-Path 'a.txt' | Should -BeFalse
    }

    It 'completes step paths under a process=qrun entry' {
        $completions = @(Get-EntryCompletion -map $script:map -language build -wordToComplete 'bootstrap.')
        $completions | Should -Contain 'bootstrap.prepare'
        $completions | Should -Contain 'bootstrap.restore'
        $completions | Should -Contain 'bootstrap.verify'
    }

    It 'surfaces step dynamic parameters through qbuild' {
        InModuleScope ConfigMap {
            param($Map)
            $params = Get-ProcessDynamicParam -Map $Map -ProcessKey 'bootstrap.restore'
            $params.Keys | Should -Contain 'Environment'
        } -Parameters @{ Map = $script:map }

        qbuild -map $script:map bootstrap.prepare
        qbuild -map $script:map bootstrap.restore -Environment prod
        Get-Content 'marker-b.txt' -Raw | Should -Match 'restored:prod'
    }

    It 'lists process=qrun entries with status output' {
        qbuild -map $script:map bootstrap.prepare

        InModuleScope ConfigMap {
            param($Map)
            Mock Write-Host
            Write-MapHelp -map $Map -invocation ([pscustomobject]@{ InvocationName = 'qbuild' }) -language build
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'bootstrap' }
            # status glyphs / step names from Write-ProcessStatus
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'prepare' }
        } -Parameters @{ Map = $script:map }
    }

    It 'supports qbuild !state show and clean' {
        { qbuild -map $script:map '!state' } | Should -Not -Throw

        qbuild -map $script:map bootstrap.prepare
        { qbuild -map $script:map '!state' show bootstrap } | Should -Not -Throw

        qbuild -map $script:map '!state' clean bootstrap
        $stateFiles = @(Get-ChildItem -Path (Join-Path $script:workDir '.configmap' 'process') -Recurse -Filter '*.state.json' -ErrorAction SilentlyContinue)
        $stateFiles.Count | Should -Be 0
    }

    It 'smoke-loads the process-mixed sample map' {
        $sampleDir = Join-Path $PSScriptRoot '..' 'samples' 'process-mixed'
        $sampleFile = Join-Path $sampleDir '.build.map.ps1'
        Copy-Item -LiteralPath $sampleFile -Destination (Join-Path $script:workDir '.build.map.ps1')
        $sampleMap = Import-ConfigMap -Map (Join-Path $script:workDir '.build.map.ps1')
        $sampleMap.Keys | Should -Contain 'build'
        $sampleMap.Keys | Should -Contain 'bootstrap'
        $sampleMap.bootstrap.process | Should -Be 'qrun'

        qbuild -map $sampleMap clean
        qbuild -map $sampleMap bootstrap.prepare
        Test-Path (Join-Path $script:workDir 'workspace' 'prepare.txt') | Should -BeTrue
    }
}
