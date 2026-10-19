BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force
}

Describe 'qrun process runner' {
    BeforeEach {
        $script:workDir = Join-Path $TestDrive ("qrun-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:workDir -Force | Out-Null
        Push-Location $script:workDir

        $script:map = [ordered]@{
            setup = [ordered]@{
                description = 'test process'
                'step-a'    = {
                    New-Item -ItemType Directory -Path 'marker-a' -Force | Out-Null
                    'a' | Set-Content (Join-Path 'marker-a' 'done.txt')
                }
                'step-b'    = {
                    if (!(Test-Path 'marker-a/done.txt')) { throw 'step-a missing' }
                    'b' | Set-Content 'marker-b.txt'
                }
                'step-c'    = {
                    'c' | Set-Content 'marker-c.txt'
                }
            }
        }
    }

    AfterEach {
        Pop-Location
    }

    It 'runs all steps in order and persists success state' {
        qrun -map $script:map setup

        Test-Path 'marker-a/done.txt' | Should -BeTrue
        Test-Path 'marker-b.txt' | Should -BeTrue
        Test-Path 'marker-c.txt' | Should -BeTrue

        $stateFiles = @(Get-ChildItem -Path (Join-Path $script:workDir '.configmap' 'process') -Recurse -Filter '*.state.json')
        $stateFiles.Count | Should -Be 1
        $state = Get-Content $stateFiles[0].FullName -Raw | ConvertFrom-Json
        $state.steps.'step-a'.status | Should -Be 'Succeeded'
        $state.steps.'step-b'.status | Should -Be 'Succeeded'
        $state.steps.'step-c'.status | Should -Be 'Succeeded'
    }

    It 'skips already succeeded steps on re-run' {
        qrun -map $script:map setup
        Remove-Item 'marker-b.txt', 'marker-c.txt' -Force

        qrun -map $script:map setup

        Test-Path 'marker-b.txt' | Should -BeFalse
        Test-Path 'marker-c.txt' | Should -BeFalse
        Test-Path 'marker-a/done.txt' | Should -BeTrue
    }

    It 'reruns succeeded steps when -Force is specified' {
        qrun -map $script:map setup
        Remove-Item 'marker-b.txt' -Force

        qrun -map $script:map setup -Force

        Test-Path 'marker-b.txt' | Should -BeTrue
        Test-Path 'marker-c.txt' | Should -BeTrue
    }

    It 'runs a single step via process.step path and respects skip rules' {
        qrun -map $script:map setup.step-a
        Test-Path 'marker-a/done.txt' | Should -BeTrue
        Test-Path 'marker-b.txt' | Should -BeFalse

        qrun -map $script:map setup.step-a
        Test-Path 'marker-b.txt' | Should -BeFalse

        qrun -map $script:map setup.step-b
        Test-Path 'marker-b.txt' | Should -BeTrue
        Test-Path 'marker-c.txt' | Should -BeFalse
    }

    It 'treats process.all as the full process' {
        qrun -map $script:map setup.all
        Test-Path 'marker-a/done.txt' | Should -BeTrue
        Test-Path 'marker-b.txt' | Should -BeTrue
        Test-Path 'marker-c.txt' | Should -BeTrue
    }

    It 'runs from a step onward with -Follow' {
        qrun -map $script:map setup.step-a

        qrun -map $script:map setup.step-b -Follow

        Test-Path 'marker-b.txt' | Should -BeTrue
        Test-Path 'marker-c.txt' | Should -BeTrue
    }

    It 'rejects -Follow without a step path' {
        { qrun -map $script:map setup -Follow } | Should -Throw '*-Follow requires a step path*'
    }

    It 'blocks starting mid-process when prior steps are incomplete' {
        { qrun -map $script:map setup.step-b } | Should -Throw '*prior steps are incomplete*'
        Test-Path 'marker-b.txt' | Should -BeFalse
    }

    It 'allows skipping incomplete prior steps with -Force' {
        # independent steps (no artifact coupling) so -Force only exercises the runner gate
        $indep = [ordered]@{
            setup = [ordered]@{
                a = { 'a' | Set-Content 'a.txt' }
                b = { 'b' | Set-Content 'b.txt' }
                c = { 'c' | Set-Content 'c.txt' }
            }
        }

        qrun -map $indep setup.b -Force
        Test-Path 'b.txt' | Should -BeTrue
        Test-Path 'a.txt' | Should -BeFalse
    }

    It 'allows -Follow mid-process with -Force when priors are incomplete' {
        $indep = [ordered]@{
            setup = [ordered]@{
                a = { 'a' | Set-Content 'a.txt' }
                b = { 'b' | Set-Content 'b.txt' }
                c = { 'c' | Set-Content 'c.txt' }
            }
        }

        qrun -map $indep setup.b -Follow -Force
        Test-Path 'b.txt' | Should -BeTrue
        Test-Path 'c.txt' | Should -BeTrue
        Test-Path 'a.txt' | Should -BeFalse
    }

    It 'records failure and resumes from the failed step' {
        $failMap = [ordered]@{
            setup = [ordered]@{
                ok   = { 'ok' | Set-Content 'ok.txt' }
                boom = { throw 'boom-error' }
                after = { 'after' | Set-Content 'after.txt' }
            }
        }

        { qrun -map $failMap setup } | Should -Throw '*boom-error*'
        Test-Path 'ok.txt' | Should -BeTrue
        Test-Path 'after.txt' | Should -BeFalse

        $stateFiles = @(Get-ChildItem -Path (Join-Path $script:workDir '.configmap' 'process') -Recurse -Filter '*.state.json')
        $state = Get-Content $stateFiles[0].FullName -Raw | ConvertFrom-Json
        $state.steps.ok.status | Should -Be 'Succeeded'
        $state.steps.boom.status | Should -Be 'Failed'
        $state.steps.boom.error | Should -Match 'boom-error'

        # fix boom and resume
        $failMap.setup.boom = { 'fixed' | Set-Content 'boom.txt' }
        qrun -map $failMap setup

        Test-Path 'boom.txt' | Should -BeTrue
        Test-Path 'after.txt' | Should -BeTrue
    }

    It 'resets state with -Reset' {
        qrun -map $script:map setup
        qrun -map $script:map setup -Reset

        $stateFiles = @(Get-ChildItem -Path (Join-Path $script:workDir '.configmap' 'process') -Recurse -Filter '*.state.json' -ErrorAction SilentlyContinue)
        $stateFiles.Count | Should -Be 0

        Remove-Item 'marker-b.txt', 'marker-c.txt' -Force
        qrun -map $script:map setup
        Test-Path 'marker-b.txt' | Should -BeTrue
    }

    It 'shows status with -Status' {
        qrun -map $script:map setup.step-a
        { qrun -map $script:map setup -Status } | Should -Not -Throw
    }

    It 'shows state with !state and !state show' {
        # list-like: all processes/steps appear even before any run
        { qrun -map $script:map '!state' } | Should -Not -Throw

        qrun -map $script:map setup.step-a
        { qrun -map $script:map '!state' show } | Should -Not -Throw
        { qrun -map $script:map '!state' show setup } | Should -Not -Throw
    }

    It 'treats bare qrun as !state show' {
        InModuleScope ConfigMap {
            param($Map)
            Mock Write-Host
            Invoke-QRun -map $Map
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'PROCESSES:' -and $ForegroundColor -eq 'Yellow' }
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'Process state' }
        } -Parameters @{ Map = $script:map }
    }

    It 'cleans state with !state clean' {
        qrun -map $script:map setup
        $stateFiles = @(Get-ChildItem -Path (Join-Path $script:workDir '.configmap' 'process') -Recurse -Filter '*.state.json')
        $stateFiles.Count | Should -Be 1

        qrun -map $script:map '!state' clean setup
        $stateFiles = @(Get-ChildItem -Path (Join-Path $script:workDir '.configmap' 'process') -Recurse -Filter '*.state.json' -ErrorAction SilentlyContinue)
        $stateFiles.Count | Should -Be 0
    }

    It 'cleans all state with !state clean' {
        qrun -map $script:map setup
        qrun -map $script:map '!state' clean
        $stateRoot = Join-Path $script:workDir '.configmap' 'process'
        if (Test-Path $stateRoot) {
            @(Get-ChildItem -Path $stateRoot -Recurse -Filter '*.state.json' -ErrorAction SilentlyContinue).Count | Should -Be 0
        }
    }

    It 'supports exec list ordering' {
        $log = [System.Collections.Generic.List[string]]::new()
        $execMap = [ordered]@{
            setup = [ordered]@{
                exec = @('second', 'first')
                second = { $log.Add('second') }
                first  = { $log.Add('first') }
            }
        }

        qrun -map $execMap setup
        $log | Should -Be @('second', 'first')
    }

    It 'creates a sample process map with !init' {
        $mapFile = Join-Path $script:workDir '.process.map.ps1'
        qrun -map $mapFile '!init'
        Test-Path $mapFile | Should -BeTrue
        (Get-Content $mapFile -Raw) | Should -Match 'setup'
    }

    It 'supports !complete -params -entry without double-binding' {
        $mapFile = Join-Path $script:workDir '.process.map.ps1'
        @'
[ordered]@{
    setup = [ordered]@{
        prepare = { 'ok' | Set-Content 'ok.txt' }
        restore = {
            param([string]$Environment = 'dev')
            "env:$Environment" | Set-Content 'env.txt'
        }
    }
}
'@ | Set-Content -LiteralPath $mapFile -Encoding utf8

        $names = @(qrun -map $mapFile '!complete' -Params -Entry setup)
        $global:LASTEXITCODE | Should -Be 0
        $names | Should -Contain 'Follow'
        $names | Should -Contain 'Force'
        $names | Should -Contain 'Environment'
    }

    It 'supports !complete -word and named -entry run' {
        $mapFile = Join-Path $script:workDir '.process.map.ps1'
        @'
[ordered]@{
    setup = [ordered]@{
        prepare = { 'ok' | Set-Content 'ok.txt' }
        restore = { 'r' | Set-Content 'r.txt' }
    }
}
'@ | Set-Content -LiteralPath $mapFile -Encoding utf8

        $words = @(qrun -map $mapFile '!complete' -Word 'setup.')
        $global:LASTEXITCODE | Should -Be 0
        $words | Should -Contain 'setup.prepare'
        $words | Should -Contain 'setup.restore'

        qrun -map $mapFile -entry setup.prepare
        Test-Path 'ok.txt' | Should -BeTrue
    }

    It 'executes skipped scriptblock and shows output when step is skipped' {
        $comments = [System.Collections.Generic.List[string]]::new()
        $skipMap = [ordered]@{
            setup = [ordered]@{
                'step-a' = @{
                    exec    = { 'a' | Set-Content 'a.txt' }
                    skipped = { return 'rule for port 123 exists' }
                }
                'step-b' = @{
                    exec    = { 'b' | Set-Content 'b.txt' }
                    skipped = {
                        return @('first comment', 'second comment')
                    }
                }
            }
        }

        qrun -map $skipMap setup

        # capture output on the second run (all steps skipped)
        $output = qrun -map $skipMap setup 6>&1 | Out-String
        $output | Should -Match 'rule for port 123 exists'
        $output | Should -Match 'first comment'
        $output | Should -Match 'second comment'
    }

    It 'shows skipped scriptblock comments in Write-ProcessStatus tree view' {
        $skipMap = [ordered]@{
            setup = [ordered]@{
                description = 'check process'
                'web'       = @{
                    exec    = { 'w' | Set-Content 'w.txt' }
                    skipped = { return 'firewall rule ok' }
                }
                'dashboard' = @{
                    exec    = { 'd' | Set-Content 'd.txt' }
                    skipped = { return 'dashboard rule ok' }
                }
            }
        }

        qrun -map $skipMap setup

        $output = qrun -map $skipMap '!state' show 6>&1 | Out-String
        $output | Should -Match 'firewall rule ok'
        $output | Should -Match 'dashboard rule ok'
    }
}
