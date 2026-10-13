BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force
}

Describe 'qconf as a qbuild process' {
    BeforeEach {
        $script:workDir = Join-Path $TestDrive ("qbuild-qconf-" + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:workDir -Force | Out-Null
        Push-Location $script:workDir

        $script:mapFile = Join-Path $script:workDir '.build.map.ps1'
        @'
[ordered]@{
    build = {
        'built' | Set-Content 'build.txt'
    }

    storage = [ordered]@{
        _settings   = @{ process = 'qconf' }
        description = 'App storage endpoint'
        options     = [ordered]@{
            local = 'L'
            prod  = 'P'
        }
        get = {
            param($ctx, $options)
            $key = if (Test-Path 'storage-active.txt') {
                (Get-Content 'storage-active.txt' -Raw).Trim()
            }
            else {
                'local'
            }
            "get:$key" | Set-Content 'storage-get.txt'
            $options[$key]
        }
        set = {
            param($ctx, $key, $value)
            $key | Set-Content 'storage-active.txt'
            "$key=$value" | Set-Content 'storage-set.txt'
        }
    }
}
'@ | Set-Content -LiteralPath $script:mapFile -Encoding utf8
    }

    AfterEach {
        Pop-Location
    }

    It 'runs ordinary build entries beside qconf entries' {
        qbuild -map $script:mapFile build

        Get-Content 'build.txt' -Raw | Should -Match 'built'
        Test-Path 'storage-get.txt' | Should -BeFalse
        Test-Path 'storage-set.txt' | Should -BeFalse
    }

    It 'gets a qconf entry by default through qbuild' {
        qbuild -map $script:mapFile storage

        Get-Content 'storage-get.txt' -Raw | Should -Match 'get:local'
        Test-Path 'storage-set.txt' | Should -BeFalse
    }

    It 'has the same default get behavior when qconf is called directly' {
        $result = qconf -map $script:mapFile storage

        $result.Path | Should -Be 'storage/'
        $result.Value | Should -Be 'L'
        @($result.Active) | Should -Contain 'local'
    }

    It 'sets an option through qbuild and a later get observes it' {
        qbuild -map $script:mapFile storage -value prod

        Get-Content 'storage-set.txt' -Raw | Should -Match 'prod=P'

        qbuild -map $script:mapFile storage
        Get-Content 'storage-get.txt' -Raw | Should -Match 'get:prod'
    }

    It 'supports explicit get and set verbs through qbuild' {
        qbuild -map $script:mapFile storage set prod
        Get-Content 'storage-set.txt' -Raw | Should -Match 'prod=P'

        $result = qbuild -map $script:mapFile storage get
        Get-Content 'storage-get.txt' -Raw | Should -Match 'get:prod'
        $result.Path | Should -Be 'storage/'
        $result.Value | Should -Be 'P'
        @($result.Active) | Should -Contain 'prod'
    }

    It 'supports explicit get and set verbs through qconf directly' {
        qconf -map $script:mapFile storage set local
        $result = qconf -map $script:mapFile storage get

        Get-Content 'storage-set.txt' -Raw | Should -Match 'local=L'
        @($result.Active) | Should -Contain 'local'
    }

    It 'rejects an unknown option key' {
        { qbuild -map $script:mapFile storage -value nope } |
            Should -Throw '*option*nope*'
    }

    It 'lists the qconf entry with its active option and available options' {
        qbuild -map $script:mapFile storage -value prod

        $output = (qbuild -map $script:mapFile list 6>&1 | Out-String)
        $output | Should -Match 'Map:\s+\./\.build\.map\.ps1'
        $output | Should -Match 'storage'
        $output | Should -Match 'prod'
        $output | Should -Match 'local'
        $output | Should -Match 'App storage endpoint'
        $output | Should -Match '├'
        $output | Should -Match 'Active'
        $output | Should -Match '└'
        $output | Should -Match 'Options'
    }

    It 'lists one entry directly through qconf' {
        $output = (qconf -map $script:mapFile list storage 6>&1 | Out-String)

        $output | Should -Match 'storage'
        $output | Should -Match 'local'
        $output | Should -Match 'prod'
        $output | Should -Match '├'
        $output | Should -Match 'Value'
        $output | Should -Match '└'
        $output | Should -Match 'Options'
    }

    It 'shows one qconf entry through qbuild using the list format' {
        qbuild -map $script:mapFile storage set prod
        $output = (qbuild -map $script:mapFile storage show 6>&1 | Out-String)

        $output | Should -Match 'storage'
        $output | Should -Match 'App storage endpoint'
        $output | Should -Match 'Active'
        $output | Should -Match 'prod'
        $output | Should -Match 'Value'
        $output | Should -Match 'P'
        $output | Should -Match 'Options'
    }

    It 'shows one entry directly through qconf' {
        $output = (qconf -map $script:mapFile storage show 6>&1 | Out-String)

        $output | Should -Match 'storage'
        $output | Should -Match 'Active'
        $output | Should -Match 'local'
        $output | Should -Match 'Options'
    }

    It 'advertises value as an opaque process parameter' {
        $params = @(qconf -map $script:mapFile '!complete' -Params -entry storage)

        $params | Should -Contain 'value'
    }

    It 'completes entry words through the process protocol' {
        $words = @(qconf -map $script:mapFile '!complete' -Word 'sto')

        $words | Should -Contain 'storage'
    }

    It 'completes explicit qconf verbs after an entry' {
        $line = "qconf -map '$script:mapFile' storage "
        $completions = @(TabExpansion2 $line $line.Length).CompletionMatches.CompletionText

        $completions | Should -Contain 'get'
        $completions | Should -Contain 'set'
        $completions | Should -Contain 'show'
    }

    It 'completes option keys after the explicit set verb' {
        $line = "qconf -map '$script:mapFile' storage set "
        $completions = @(TabExpansion2 $line $line.Length).CompletionMatches.CompletionText

        $completions | Should -Contain 'local'
        $completions | Should -Contain 'prod'
    }

    It 'completes option keys for the value shorthand' {
        $line = "qconf -map '$script:mapFile' storage -value "
        $completions = @(TabExpansion2 $line $line.Length).CompletionMatches.CompletionText

        $completions | Should -Contain 'local'
        $completions | Should -Contain 'prod'
    }

    It 'completes qconf verbs through qbuild' {
        $line = "qbuild -map '$script:mapFile' storage "
        $completions = @(TabExpansion2 $line $line.Length).CompletionMatches.CompletionText

        $completions | Should -Contain 'get'
        $completions | Should -Contain 'set'
        $completions | Should -Contain 'show'
    }

    It 'completes qconf option keys through qbuild' {
        $line = "qbuild -map '$script:mapFile' storage set "
        $completions = @(TabExpansion2 $line $line.Length).CompletionMatches.CompletionText

        $completions | Should -Contain 'local'
        $completions | Should -Contain 'prod'
    }

    It 'does not suggest -value after a positional set option key' {
        @'
[ordered]@{
    env = [ordered]@{
        _settings = @{ process = 'qconf' }
        options   = [ordered]@{ local = 'L'; dev = 'D' }
        get       = { param($ctx, $options) '' }
        set       = { param($ctx, $key, $value, [string]$tenant) }
    }
}
'@ | Set-Content -LiteralPath $script:mapFile -Encoding utf8

        $line = "qbuild -map '$script:mapFile' env set local -"
        $completions = @(TabExpansion2 $line $line.Length).CompletionMatches.CompletionText

        $completions | Should -Not -Contain '-value'
        $completions | Should -Contain '-tenant'
    }

    It 'keeps legacy named get and set commands working' {
        qconf -map $script:mapFile -command set -entry storage -value local
        $result = qconf -map $script:mapFile -command get -entry storage

        Get-Content 'storage-set.txt' -Raw | Should -Match 'local=L'
        @($result.Active) | Should -Contain 'local'
    }

    It 'forwards opaque set parameters for option-less qconf entries' {
        @'
[ordered]@{
    env = [ordered]@{
        _settings   = @{ process = 'qconf' }
        description = 'Environment / tenant selection'
        get         = {
            param($ctx, $options)
            if (Test-Path 'env.txt') {
                (Get-Content 'env.txt' -Raw).Trim()
            }
            else {
                ''
            }
        }
        set         = {
            param($ctx, $key, $value, [string]$tenant)
            if ([string]::IsNullOrWhiteSpace($tenant)) {
                throw "Set env requires -tenant <name>."
            }
            $tenant | Set-Content 'env.txt'
            "$key|$tenant" | Set-Content 'env-set.txt'
        }
    }
}
'@ | Set-Content -LiteralPath $script:mapFile -Encoding utf8

        qbuild -map $script:mapFile env set dev -tenant abc

        Get-Content 'env.txt' -Raw | Should -Match 'abc'
        Get-Content 'env-set.txt' -Raw | Should -Match 'dev\|abc'

        $result = qbuild -map $script:mapFile env get
        $result.Value | Should -Be 'abc'
    }

    It 'forwards nameless positional set parameters after the option key' {
        @'
[ordered]@{
    env = [ordered]@{
        _settings = @{ process = 'qconf' }
        get       = {
            param($ctx, $options)
            if (Test-Path 'env.txt') { (Get-Content 'env.txt' -Raw).Trim() } else { '' }
        }
        set       = {
            param($ctx, $key, $value, [string]$tenant)
            if ([string]::IsNullOrWhiteSpace($tenant)) {
                throw "Set env requires tenant."
            }
            $tenant | Set-Content 'env.txt'
            "$key|$tenant" | Set-Content 'env-set.txt'
        }
    }
}
'@ | Set-Content -LiteralPath $script:mapFile -Encoding utf8

        qbuild -map $script:mapFile env set local tenant_1

        Get-Content 'env.txt' -Raw | Should -Match 'tenant_1'
        Get-Content 'env-set.txt' -Raw | Should -Match 'local\|tenant_1'
    }

    It 'advertises custom set parameters through !complete -params' {
        @'
[ordered]@{
    env = [ordered]@{
        _settings = @{ process = 'qconf' }
        get       = { param($ctx, $options) '' }
        set       = { param($ctx, $key, $value, [string]$tenant) }
    }
}
'@ | Set-Content -LiteralPath $script:mapFile -Encoding utf8

        $params = @(qconf -map $script:mapFile '!complete' -Params -entry env)

        $params | Should -Contain 'value'
        $params | Should -Contain 'tenant'
    }

    It 'smoke-runs the mixed process sample' {
        $sampleFile = Join-Path $PSScriptRoot '..' 'samples' 'process-mixed' '.build.map.ps1'
        Copy-Item -LiteralPath $sampleFile -Destination $script:mapFile -Force

        qbuild -map $script:mapFile build
        qbuild -map $script:mapFile storage set prod
        qbuild -map $script:mapFile storage get
        qbuild -map $script:mapFile env set dev -tenant abc

        Test-Path 'out/build.txt' | Should -BeTrue
        Get-Content 'workspace/storage.txt' -Raw | Should -Match 'prod'
        Get-Content 'workspace/env.txt' -Raw | Should -Match 'abc'

        $line = "qbuild -map '$script:mapFile' env set "
        $completions = @(TabExpansion2 $line $line.Length).CompletionMatches.CompletionText
        $completions | Should -Contain 'local'
        $completions | Should -Contain 'dev'
        $completions | Should -Contain 'prod'
    }
}
