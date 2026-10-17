BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force
}

Describe 'qbuild _settings.process=steps forwarding' {
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
        _settings   = @{ process = 'steps' }
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
                _settings = @{ process = 'steps' }
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
        _settings = @{ process = 'steps' }
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

    It 'completes step paths under an _settings.process=steps entry' {
        $map = Import-ConfigMap -Map $script:mapFile
        $completions = @(Get-EntryCompletion -map $map -language build -wordToComplete 'bootstrap.')
        $completions | Should -Contain 'bootstrap.prepare'
        $completions | Should -Contain 'bootstrap.restore'
        $completions | Should -Contain 'bootstrap.verify'
    }

    It 'routes entry completion through process !complete -word via the qrun CLI' {
        InModuleScope ConfigMap {
            param($MapFile)
            $words = @(Get-ConfigMapProcessCompleteWord -ProcessName 'qrun' -MapPath $MapFile -Word 'bootstrap.')
            $words | Should -Contain 'bootstrap.prepare'
            $words | Should -Contain 'bootstrap.restore'
            $words | Should -Contain 'bootstrap.verify'

            # steps is an in-process handler; external process-name discovery stays empty
            $names = @(Get-ConfigMapProcessNamesInMap -Map (Import-ConfigMap -Map $MapFile))
            $names | Should -Not -Contain 'steps'
            $names | Should -Not -Contain 'qrun'

            (Get-ConfigMapProcessCanonicalName -ProcessName 'qrun') | Should -Be 'steps'
            (Get-ConfigMapProcessHandler -Name 'qrun').Name | Should -Be 'steps'
            (Get-ConfigMapProcessHandler -Name 'steps').Name | Should -Be 'steps'
        } -Parameters @{ MapFile = $script:mapFile }
    }

    It 'accepts legacy process=qrun as an alias for steps' {
        $legacyFile = Join-Path $script:workDir 'legacy.build.map.ps1'
        @'
[ordered]@{
    bootstrap = [ordered]@{
        _settings = @{ process = 'qrun' }
        prepare   = { 'legacy' | Set-Content 'legacy.txt' }
    }
}
'@ | Set-Content -LiteralPath $legacyFile -Encoding utf8

        qbuild -map $legacyFile bootstrap.prepare
        Get-Content 'legacy.txt' -Raw | Should -Match 'legacy'
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

    It 'lists _settings.process=steps entries with status output' {
        qbuild -map $script:mapFile bootstrap.prepare

        Mock Write-Host -ModuleName ConfigMap
        qbuild -map $script:mapFile list
        Should -Invoke Write-Host -ModuleName ConfigMap -ParameterFilter { "$Object" -match 'bootstrap' }
        Should -Invoke Write-Host -ModuleName ConfigMap -ParameterFilter { "$Object" -match 'prepare' }
    }

    It 'runs an entry that explicitly selects the exec process' {
        @'
[ordered]@{
    task = @{
        _settings = @{ process = 'exec' }
        exec = { 'ran' | Set-Content 'qbuild-process.txt' }
    }
}
'@ | Set-Content -LiteralPath $script:mapFile -Encoding utf8

        qbuild -map $script:mapFile task
        Get-Content 'qbuild-process.txt' -Raw | Should -Match 'ran'
    }

    It 'registers exec as the default in-process handler' {
        InModuleScope ConfigMap {
            $handler = Get-ConfigMapProcessHandler -Name 'exec'
            $handler.Name | Should -Be 'exec'
            $handler.Invoke | Should -Not -BeNullOrEmpty
            $handler.GetDynamicParam | Should -Not -BeNullOrEmpty
            $handler.WriteListEntry | Should -BeNullOrEmpty
        }
    }

    It 'dispatches a registered in-process handler without a source file' {
        $probeFile = Join-Path $script:workDir 'probed.txt'
        InModuleScope ConfigMap {
            param($ProbeFile)
            $script:QProbeFile = $ProbeFile
            Register-ConfigMapProcess -Name 'qprobe' -Invoke {
                param($Context)
                "probed:$($Context.Entry)" | Set-Content -LiteralPath $script:QProbeFile
            }
        } -Parameters @{ ProbeFile = $probeFile }

        try {
            $map = @{
                task = @{
                    _settings = @{ process = 'qprobe' }
                    exec      = { 'should-not-run' | Set-Content 'ran.txt' }
                }
            }

            qbuild -map $map task
            Get-Content -LiteralPath $probeFile -Raw | Should -Match 'probed:task'
            Test-Path 'ran.txt' | Should -BeFalse
        }
        finally {
            InModuleScope ConfigMap {
                Unregister-ConfigMapProcess -Name 'qprobe'
                Remove-Variable -Name QProbeFile -Scope Script -ErrorAction SilentlyContinue
            }
        }
    }

    It 'smoke-loads the process-mixed sample map' {
        $sampleDir = Join-Path $PSScriptRoot '..' 'samples' 'process-mixed'
        $sampleFile = Join-Path $sampleDir '.build.map.ps1'
        $localMap = Join-Path $script:workDir '.build.map.ps1'
        Copy-Item -LiteralPath $sampleFile -Destination $localMap

        $sampleMap = Import-ConfigMap -Map $localMap
        $sampleMap.Keys | Should -Contain 'build'
        $sampleMap.Keys | Should -Contain 'bootstrap'
        $sampleMap.bootstrap._settings.process | Should -Be 'steps'

        qbuild -map $localMap clean
        qbuild -map $localMap bootstrap.prepare
        Test-Path (Join-Path $script:workDir 'workspace' 'prepare.txt') | Should -BeTrue
    }
}

Describe 'qbuild in-process process handlers' {
    BeforeEach {
        $script:workDir = Join-Path $TestDrive ("qbuild-handler-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:workDir -Force | Out-Null
        Push-Location $script:workDir
    }

    AfterEach {
        Pop-Location
    }

    It 'runs an entry when process is explicitly exec' {
        $mapFile = Join-Path $script:workDir '.build.map.ps1'
        @'
@{
    build = @{
        _settings = @{ process = 'exec' }
        exec = { 'explicit-exec' | Set-Content 'explicit.txt' }
    }
}
'@ | Set-Content -LiteralPath $mapFile -Encoding utf8

        qbuild -map $mapFile build
        Get-Content 'explicit.txt' -Raw | Should -Match 'explicit-exec'
    }

    It 'registers exec with Invoke and GetDynamicParam and no WriteListEntry' {
        InModuleScope ConfigMap {
            $handler = Get-ConfigMapProcessHandler -Name exec
            $null -ne $handler.Invoke | Should -BeTrue
            $null -ne $handler.GetDynamicParam | Should -BeTrue
            $null -eq $handler.WriteListEntry | Should -BeTrue
            (Get-ConfigMapProcessHandler -Name Exec).Name | Should -Be 'exec'
        }
    }

    It 'runs a registered handler from an in-memory map without exec' {
        InModuleScope ConfigMap {
            Register-ConfigMapProcess -Name qprobe -Invoke {
                param($Context)
                $Context.Entry | Set-Content 'probe-entry.txt'
            }
            try {
                $map = @{
                    job = @{
                        _settings = @{ process = 'qprobe' }
                        exec = { 'exec-ran' | Set-Content 'exec.txt' }
                    }
                }

                qbuild -map $map job

                Get-Content 'probe-entry.txt' -Raw | Should -Match 'job'
                Test-Path 'exec.txt' | Should -BeFalse
            }
            finally {
                Unregister-ConfigMapProcess -Name qprobe
            }
        }
    }

    It 'does not delegate a missing exec handler to an external command' {
        $mapFile = Join-Path $script:workDir '.build.map.ps1'
        @'
@{
    build = { 'ran' | Set-Content 'ran.txt' }
}
'@ | Set-Content -LiteralPath $mapFile -Encoding utf8

        InModuleScope ConfigMap {
            param($MapFile)
            Unregister-ConfigMapProcess -Name exec
            Mock Invoke-ConfigMapProcessCli { throw 'cli-was-called' }
            try {
                { qbuild -map $MapFile build } | Should -Throw '*no in-process handler*'
                Test-Path 'ran.txt' | Should -BeFalse
            }
            finally {
                Register-ConfigMapExecProcess
            }
        } -Parameters @{ MapFile = $mapFile }
    }

    It 'does not delegate process=qbuild back to the qbuild host alias' {
        $mapFile = Join-Path $script:workDir '.build.map.ps1'
        @'
@{
    build = @{
        _settings = @{ process = 'qbuild' }
        exec = { 'ran' | Set-Content 'ran.txt' }
    }
}
'@ | Set-Content -LiteralPath $mapFile -Encoding utf8

        InModuleScope ConfigMap {
            param($MapFile)
            Mock Invoke-ConfigMapProcessCli { throw 'cli-was-called' }
            { qbuild -map $MapFile build } | Should -Throw '*no in-process handler*'
            Test-Path 'ran.txt' | Should -BeFalse
        } -Parameters @{ MapFile = $mapFile }
    }
}
