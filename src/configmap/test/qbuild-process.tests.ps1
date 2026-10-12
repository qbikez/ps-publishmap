BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force
}

Describe 'qbuild _settings.process=qrun forwarding' {
    BeforeEach {
        $script:workDir = Join-Path $TestDrive ("qbuild-process-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:workDir -Force | Out-Null
        Push-Location $script:workDir

        # Contract is path-only handoff; write the map to a file for all invokes.
        $script:mapFile = Join-Path $script:workDir '.build.map.ps1'
        @'
[ordered]@{
    build = {
        param(
            [ValidateSet('Debug', 'Release')]
            [string]$Configuration = 'Debug'
        )
        "built:$Configuration" | Set-Content 'build.txt'
    }

    bootstrap = [ordered]@{
        _settings   = @{ process = 'qrun' }
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
'@ | Set-Content -LiteralPath $script:mapFile -Encoding utf8
    }

    AfterEach {
        Pop-Location
    }

    It 'still runs default qbuild entries' {
        qbuild -map $script:mapFile build -Configuration Release
        Get-Content 'build.txt' -Raw | Should -Match 'built:Release'
    }

    It 'forwards full process run and persists success state' {
        qbuild -map $script:mapFile bootstrap

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

    It 'does not delegate a process entry when an in-memory map has no source file' {
        $map = @{
            bootstrap = @{
                _settings = @{ process = 'qrun' }
                prepare = { 'prepared' | Set-Content 'in-memory-process.txt' }
            }
        }

        { qbuild -map $map bootstrap } | Should -Throw '*the map has no _sourceFile*'
        Test-Path 'in-memory-process.txt' | Should -BeFalse
    }

    It 'skips already succeeded steps on re-run' {
        qbuild -map $script:mapFile bootstrap
        Remove-Item 'marker-b.txt', 'marker-c.txt' -Force

        qbuild -map $script:mapFile bootstrap

        Test-Path 'marker-b.txt' | Should -BeFalse
        Test-Path 'marker-c.txt' | Should -BeFalse
        Test-Path 'marker-a/done.txt' | Should -BeTrue
    }

    It 'reruns succeeded steps when -Force is specified' {
        qbuild -map $script:mapFile bootstrap
        Remove-Item 'marker-b.txt' -Force

        qbuild -map $script:mapFile bootstrap -Force

        Test-Path 'marker-b.txt' | Should -BeTrue
        Test-Path 'marker-c.txt' | Should -BeTrue
    }

    It 'runs a single step via process.step path' {
        qbuild -map $script:mapFile bootstrap.prepare
        Test-Path 'marker-a/done.txt' | Should -BeTrue
        Test-Path 'marker-b.txt' | Should -BeFalse

        qbuild -map $script:mapFile bootstrap.restore
        Test-Path 'marker-b.txt' | Should -BeTrue
        Test-Path 'marker-c.txt' | Should -BeFalse
    }

    It 'runs from a step onward with -Follow' {
        qbuild -map $script:mapFile bootstrap.prepare

        qbuild -map $script:mapFile bootstrap.restore -Follow

        Test-Path 'marker-b.txt' | Should -BeTrue
        Test-Path 'marker-c.txt' | Should -BeTrue
    }

    It 'rejects -Follow without a step path' {
        { qbuild -map $script:mapFile bootstrap -Follow } | Should -Throw '*-Follow requires a step path*'
    }

    It 'blocks starting mid-process when prior steps are incomplete' {
        { qbuild -map $script:mapFile bootstrap.restore } | Should -Throw '*prior steps are incomplete*'
        Test-Path 'marker-b.txt' | Should -BeFalse
    }

    It 'allows skipping incomplete prior steps with -Force' {
        $indepFile = Join-Path $script:workDir 'indep.build.map.ps1'
        @'
[ordered]@{
    setup = [ordered]@{
        _settings = @{ process = 'qrun' }
        a         = { 'a' | Set-Content 'a.txt' }
        b         = { 'b' | Set-Content 'b.txt' }
        c         = { 'c' | Set-Content 'c.txt' }
    }
}
'@ | Set-Content -LiteralPath $indepFile -Encoding utf8

        qbuild -map $indepFile setup.b -Force
        Test-Path 'b.txt' | Should -BeTrue
        Test-Path 'a.txt' | Should -BeFalse
    }

    It 'completes step paths under an _settings.process=qrun entry' {
        $map = Import-ConfigMap -Map $script:mapFile
        $completions = @(Get-EntryCompletion -map $map -language build -wordToComplete 'bootstrap.')
        $completions | Should -Contain 'bootstrap.prepare'
        $completions | Should -Contain 'bootstrap.restore'
        $completions | Should -Contain 'bootstrap.verify'
    }

    It 'routes entry completion through process !complete -word' {
        InModuleScope ConfigMap {
            param($MapFile)
            $words = @(Get-ConfigMapProcessCompleteWord -ProcessName 'qrun' -MapPath $MapFile -Word 'bootstrap.')
            $words | Should -Contain 'bootstrap.prepare'
            $words | Should -Contain 'bootstrap.restore'
            $words | Should -Contain 'bootstrap.verify'

            $names = @(Get-ConfigMapProcessNamesInMap -Map (Import-ConfigMap -Map $MapFile))
            $names | Should -Contain 'qrun'
        } -Parameters @{ MapFile = $script:mapFile }
    }

    It 'delegates run with explicit -entry' {
        InModuleScope ConfigMap {
            param($MapFile)
            $splat = ConvertTo-ConfigMapProcessSplat -MapPath $MapFile -Entry 'bootstrap.prepare'
            $splat.entry | Should -Be 'bootstrap.prepare'
            $splat.Keys | Should -Not -Contain 'command'
        } -Parameters @{ MapFile = $script:mapFile }

        qbuild -map $script:mapFile bootstrap.prepare
        Test-Path 'marker-a/done.txt' | Should -BeTrue
    }

    It 'forwards process step parameters end-to-end' {
        qbuild -map $script:mapFile bootstrap.prepare
        qbuild -map $script:mapFile bootstrap.restore -Environment prod
        Get-Content 'marker-b.txt' -Raw | Should -Match 'restored:prod'
    }

    It 'lists _settings.process=qrun entries with status output' {
        qbuild -map $script:mapFile bootstrap.prepare

        Mock Write-Host -ModuleName ConfigMap
        qbuild -map $script:mapFile list
        Should -Invoke Write-Host -ModuleName ConfigMap -ParameterFilter { "$Object" -match 'bootstrap' }
        Should -Invoke Write-Host -ModuleName ConfigMap -ParameterFilter { "$Object" -match 'prepare' }
    }

    It 'smoke-loads the process-mixed sample map' {
        $sampleDir = Join-Path $PSScriptRoot '..' 'samples' 'process-mixed'
        $sampleFile = Join-Path $sampleDir '.build.map.ps1'
        $localMap = Join-Path $script:workDir '.build.map.ps1'
        Copy-Item -LiteralPath $sampleFile -Destination $localMap

        $sampleMap = Import-ConfigMap -Map $localMap
        $sampleMap.Keys | Should -Contain 'build'
        $sampleMap.Keys | Should -Contain 'bootstrap'
        $sampleMap.bootstrap._settings.process | Should -Be 'qrun'

        qbuild -map $localMap clean
        qbuild -map $localMap bootstrap.prepare
        Test-Path (Join-Path $script:workDir 'workspace' 'prepare.txt') | Should -BeTrue
    }
}
