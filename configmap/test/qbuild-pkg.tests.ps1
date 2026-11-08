BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force

    # Probe stands in for the real bun/npm executables; function lookup wins over applications.
    function global:bun { $global:PkgCalls += , @{ Tool = 'bun'; Args = @($args); Cwd = (Get-Location).Path }; $global:LASTEXITCODE = 0 }
    function global:npm { $global:PkgCalls += , @{ Tool = 'npm'; Args = @($args); Cwd = (Get-Location).Path }; $global:LASTEXITCODE = 0 }
}

AfterAll {
    Remove-Item function:global:bun, function:global:npm -ErrorAction SilentlyContinue
    Remove-Variable PkgCalls -Scope Global -ErrorAction SilentlyContinue
}

Describe 'qbuild package script proxy' {
    BeforeEach {
        $global:PkgCalls = @()
        $script:workDir = Join-Path $TestDrive ("qbuild-pkg-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:workDir -Force | Out-Null
        Push-Location $script:workDir
        '{ "scripts": { "dev": "vite", "build": "tsc -b" } }' | Set-Content package.json
    }

    AfterEach {
        Pop-Location
    }

    Context 'explicit _settings.process' {
        BeforeEach {
            "@{ web = @{ description = 'Frontend'; _settings = @{ process = 'bun' } } }" |
                Set-Content (Join-Path $script:workDir '.build.map.ps1')
        }

        It 'lists the entry with the same indent as other commands' {
            ((qbuild list 6>&1) -join '') | Should -BeLike '*    web  Frontend*'
        }

        It 'runs a script entry as bun run in the map directory' {
            qbuild web.dev

            $global:PkgCalls.Count | Should -Be 1
            $global:PkgCalls[0].Args | Should -Be @('run', 'dev')
            $global:PkgCalls[0].Cwd | Should -Be $script:workDir
        }

        It 'forwards arguments after --' {
            qbuild web.dev -- --no-build --watch -d=1

            $global:PkgCalls[0].Args | Should -Be @('run', 'dev', '--no-build', '--watch', '-d=1')
        }

        It 'lists scripts with no action' {
            $out = qbuild web 6>&1 | Out-String

            $out | Should -Match 'dev'
            $out | Should -Match 'vite'
            $out | Should -Match 'build'
            $global:PkgCalls.Count | Should -Be 0
        }

        It 'lists scripts as entries in the regular qbuild list format' {
            $out = (qbuild web 6>&1) -join ''

            $out | Should -Match 'COMMANDS:'
            $out | Should -BeLike '*    web.dev    vite*'
            $out | Should -BeLike '*    web.build  tsc -b*'
        }

        It 'lists scripts with the list action' {
            $out = qbuild web list 6>&1 | Out-String

            $out | Should -Match 'tsc -b'
            $global:PkgCalls.Count | Should -Be 0
        }

        It 'throws for an unknown script entry and names the available ones' {
            { qbuild web.nope } | Should -Throw -ExpectedMessage '*nope*web.dev*web.build*'
            $global:PkgCalls.Count | Should -Be 0
        }

        It 'rejects a script name given as an action and points to the entry form' {
            { qbuild web dev } | Should -Throw -ExpectedMessage "*'dev'*web.dev*"
            $global:PkgCalls.Count | Should -Be 0
        }

        It 'does not read package.json for qbuild list' {
            'not json' | Set-Content package.json

            { qbuild list 6>&1 | Out-Null } | Should -Not -Throw
        }

        It 'completes only actions after the entry' {
            $line = 'qbuild web '
            $result = @((TabExpansion2 $line $line.Length).CompletionMatches.CompletionText)

            $result | Should -Be @('list')
        }

        It 'completes script entries after the entry and a dot' {
            $line = 'qbuild web.'
            $result = @((TabExpansion2 $line $line.Length).CompletionMatches.CompletionText)

            $result | Should -Contain 'web.dev'
            $result | Should -Contain 'web.build'
            $result | Should -Not -Contain 'web.list'
        }

        It 'completes a partial script entry' {
            $line = 'qbuild web.bu'
            $result = @((TabExpansion2 $line $line.Length).CompletionMatches.CompletionText)

            $result | Should -Be @('web.build')
        }
    }

    Context 'nested entry' {
        It 'runs a script of a package entry inside a group' {
            "@{ front = @{ web = @{ _settings = @{ process = 'bun' } } } }" | Set-Content .build.map.ps1

            qbuild front.web.build

            $global:PkgCalls[0].Args | Should -Be @('run', 'build')
        }
    }

    Context 'exec entries' {
        It 'still reports an unknown child of an exec entry as not found' {
            "@{ clean = { 'cleaned' } }" | Set-Content .build.map.ps1

            { qbuild clean.nope } | Should -Throw -ExpectedMessage "*'clean.nope' not found*"
        }
    }

    Context 'npm' {
        It 'inserts -- before script arguments' {
            "@{ web = @{ _settings = @{ process = 'npm' } } }" | Set-Content .build.map.ps1

            qbuild web.dev -- --watch

            $global:PkgCalls[0].Tool | Should -Be 'npm'
            $global:PkgCalls[0].Args | Should -Be @('run', 'dev', '--', '--watch')
        }
    }
}
