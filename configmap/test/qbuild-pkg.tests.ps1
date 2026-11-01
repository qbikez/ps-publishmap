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

        It 'runs a script as bun run in the map directory' {
            qbuild web dev

            $global:PkgCalls.Count | Should -Be 1
            $global:PkgCalls[0].Args | Should -Be @('run', 'dev')
            $global:PkgCalls[0].Cwd | Should -Be $script:workDir
        }

        It 'forwards arguments after --' {
            qbuild web dev -- --no-build --watch -d=1

            $global:PkgCalls[0].Args | Should -Be @('run', 'dev', '--no-build', '--watch', '-d=1')
        }

        It 'lists scripts with no action' {
            $out = qbuild web 6>&1 | Out-String

            $out | Should -Match 'dev'
            $out | Should -Match 'vite'
            $out | Should -Match 'build'
            $global:PkgCalls.Count | Should -Be 0
        }

        It 'lists scripts with the list action' {
            $out = qbuild web list 6>&1 | Out-String

            $out | Should -Match 'tsc -b'
            $global:PkgCalls.Count | Should -Be 0
        }

        It 'throws for an unknown script and names the available ones' {
            { qbuild web nope } | Should -Throw -ExpectedMessage '*nope*dev*build*'
            $global:PkgCalls.Count | Should -Be 0
        }

        It 'does not read package.json for qbuild list' {
            'not json' | Set-Content package.json

            { qbuild list 6>&1 | Out-Null } | Should -Not -Throw
        }

        It 'completes script names' {
            $ast = [System.Management.Automation.Language.Parser]::ParseInput('qbuild web ', [ref]$null, [ref]$null).EndBlock.Statements[0].PipelineElements[0]
            $completer = (Get-Command qbuild).Parameters['ProcessAction'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
                Select-Object -First 1

            $result = @(& $completer.ScriptBlock 'qbuild' 'ProcessAction' '' $ast @{ entry = 'web' })

            $result | Should -Contain 'dev'
            $result | Should -Contain 'build'
            $result | Should -Contain 'list'
        }
    }

    Context 'npm' {
        It 'inserts -- before script arguments' {
            "@{ web = @{ _settings = @{ process = 'npm' } } }" | Set-Content .build.map.ps1

            qbuild web dev -- --watch

            $global:PkgCalls[0].Tool | Should -Be 'npm'
            $global:PkgCalls[0].Args | Should -Be @('run', 'dev', '--', '--watch')
        }
    }
}
