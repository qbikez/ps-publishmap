BeforeAll {
    . "$PSScriptRoot\..\functions\plugins.ps1"
    . "$PSScriptRoot\..\handlers\qconf\config-helpers.ps1"
    . "$PSScriptRoot\..\functions\plugins-init.ps1" -PluginsPath "$PSScriptRoot\..\plugins"
    # Standalone dot-sourcing has no module scope to lazy-load into: load the implementation directly.
    . "$PSScriptRoot\..\plugins\plugin-user-secrets\user-secrets.ps1"
    (Get-ConfigMapValuePrefix 'user-secrets:').plugin.implementationLoaded = $true

    # Stands in for the dotnet CLI: records each call and prints $script:dotnetOutput.
    function dotnet {
        $script:dotnetCalls += , @($args)
        $global:LASTEXITCODE = $script:dotnetExit
        $script:dotnetOutput
    }

    function script:Set-StoreFile([string]$Id, [string]$Content = '{}') {
        Set-Content -LiteralPath (Get-UserSecretsStorePath $Id) -Value $Content
    }
}

Describe 'user-secrets plugin' {
    BeforeEach {
        Clear-UserSecretsCache
        $script:dotnetCalls = @()
        $script:dotnetExit = 0
        # What `dotnet user-secrets list --json` prints: the JSON between marker lines.
        $script:dotnetOutput = @(
            '//BEGIN'
            '{'
            '  "Api:Key": "a=b=c",'
            '  "Multi": "line1\nline2",'
            '  "Plain": "value"'
            '}'
            '//END'
        )
        # Keep the cache stamp away from the real user secrets store.
        $script:storeRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:storeRoot | Out-Null
        Mock Get-UserSecretsStorePath { Join-Path $script:storeRoot "$Id.json" }
    }

    It 'registers user-secrets: as a secret prefix, so qconf masks its values' {
        (Get-ConfigMapValuePrefix 'user-secrets:').secret | Should -BeTrue
        Get-ConfigMapSecretValuePrefix | Should -Contain 'user-secrets:'
    }

    Context 'get-user-secrets -Id' {
        It 'lists the store with --id and --json' {
            get-user-secrets -Id 'my-app' | Out-Null

            $script:dotnetCalls[0] | Should -Be @('user-secrets', 'list', '--id', 'my-app', '--json')
        }

        It 'parses the JSON between the marker lines, keeping = and newlines in values' {
            $secrets = get-user-secrets -Id 'my-app'

            $secrets['Api:Key'] | Should -Be 'a=b=c'
            $secrets['Multi'] | Should -Be "line1`nline2"
            $secrets['Plain'] | Should -Be 'value'
            $secrets.Count | Should -Be 3
        }

        It 'looks keys up case-insensitively, like .NET configuration' {
            (get-user-secrets -Id 'my-app')['api:key'] | Should -Be 'a=b=c'
        }

        It 'returns an empty table for an empty store' {
            $script:dotnetOutput = '//BEGIN', '{}', '//END'

            $secrets = get-user-secrets -Id 'empty'

            $secrets | Should -BeOfType [hashtable]
            $secrets.Count | Should -Be 0
            $LASTEXITCODE | Should -Be 0
        }

        It 'returns an empty table and a non-zero exit code when dotnet fails' {
            $script:dotnetExit = 1

            (get-user-secrets -Id 'broken').Count | Should -Be 0
            $LASTEXITCODE | Should -Not -Be 0
        }

        It 'warns without the output when it is not JSON' {
            $script:dotnetOutput = '//BEGIN', '{ "Api:Key": "leaky-secret"', '//END'

            $out = get-user-secrets -Id 'garbled' 3>&1
            $warnings = @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            $warnings.Count | Should -Be 1
            "$warnings" | Should -Not -Match 'leaky-secret'
            @($out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0].Count | Should -Be 0
            $LASTEXITCODE | Should -Not -Be 0
        }
    }

    Context 'get-user-secrets -dir' {
        It 'lists the project with --project and --json' {
            get-user-secrets 'src/App' | Out-Null

            $script:dotnetCalls[0] | Should -Be @('user-secrets', 'list', '--project', 'src/App', '--json')
        }

        It 'keeps working for positional callers' {
            (get-user-secrets 'src/App')['Plain'] | Should -Be 'value'
        }
    }

    Context 'cache' {
        It 'lists a store once while it does not change' {
            Set-StoreFile 'cached'

            get-user-secrets -Id 'cached' | Out-Null
            (get-user-secrets -Id 'cached')['Plain'] | Should -Be 'value'

            $script:dotnetCalls.Count | Should -Be 1
            $LASTEXITCODE | Should -Be 0
        }

        It 'caches each store separately' {
            Set-StoreFile 'one'
            Set-StoreFile 'two'

            get-user-secrets -Id 'one' | Out-Null
            get-user-secrets -Id 'two' | Out-Null
            get-user-secrets -Id 'one' | Out-Null

            $script:dotnetCalls.Count | Should -Be 2
        }

        It 'lists again after the store changes' {
            Set-StoreFile 'changing'
            get-user-secrets -Id 'changing' | Out-Null

            Set-StoreFile 'changing' '{ "Plain": "changed value" }'
            get-user-secrets -Id 'changing' | Out-Null

            $script:dotnetCalls.Count | Should -Be 2
        }

        It 'does not cache failures' {
            Set-StoreFile 'retry'
            $script:dotnetExit = 1
            get-user-secrets -Id 'retry' | Out-Null

            $script:dotnetExit = 0
            (get-user-secrets -Id 'retry')['Plain'] | Should -Be 'value'
        }

        It 'hands out copies, so a caller cannot change the cache' {
            Set-StoreFile 'copy'
            (get-user-secrets -Id 'copy')['Plain'] = 'tampered'

            (get-user-secrets -Id 'copy')['Plain'] | Should -Be 'value'
        }

        It 'caches a project listing by the UserSecretsId in its project file' {
            $project = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $project | Out-Null
            Set-Content (Join-Path $project 'App.csproj') '<Project><PropertyGroup><UserSecretsId>from-csproj</UserSecretsId></PropertyGroup></Project>'
            Set-StoreFile 'from-csproj'

            get-user-secrets $project | Out-Null
            get-user-secrets $project | Out-Null

            $script:dotnetCalls.Count | Should -Be 1
        }

        It 'does not cache a project listing whose store it cannot find' {
            get-user-secrets (Join-Path $TestDrive 'no-such-project') | Out-Null
            get-user-secrets (Join-Path $TestDrive 'no-such-project') | Out-Null

            $script:dotnetCalls.Count | Should -Be 2
        }
    }

    Context 'resolve-value' {
        It 'resolves from the store named by -userSecretsId' {
            resolve-value 'user-secrets:Multi' -userSecretsId 'my-app' | Should -Be "line1`nline2"

            $script:dotnetCalls[0] | Should -Be @('user-secrets', 'list', '--id', 'my-app', '--json')
        }

        It 'resolves from the project in -dir without an id' {
            resolve-value 'user-secrets:Plain' -dir 'src/App' | Should -Be 'value'

            $script:dotnetCalls[0] | Should -Be @('user-secrets', 'list', '--project', 'src/App', '--json')
        }

        It 'suggests --id when a secret is missing from an id store' {
            $out = resolve-value 'user-secrets:Nope' -userSecretsId 'my-app' 3>&1
            $warning = @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            "$warning" | Should -Match ([regex]::Escape('dotnet user-secrets --id my-app set Nope <value>'))
            $out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] } | Should -Be 'user-secrets:Nope'
        }

        It 'suggests -p when a secret is missing from a project store' {
            $out = resolve-value 'user-secrets:Nope' -dir 'src/App' 3>&1
            $warning = @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            "$warning" | Should -Match ([regex]::Escape('dotnet user-secrets -p src/App set Nope <value>'))
        }

        It 'warns and keeps the literal when the store cannot be listed' {
            $script:dotnetExit = 1

            $out = resolve-value 'user-secrets:Plain' -userSecretsId 'my-app' 3>&1
            "$(@($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }))" | Should -Match '--id my-app'
            $out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] } | Should -Be 'user-secrets:Plain'
        }

        It 'uses an already-listed Secrets table without calling dotnet' {
            resolve-value 'user-secrets:k' -secrets @{ k = 'given' } -userSecretsId 'my-app' | Should -Be 'given'

            $script:dotnetCalls.Count | Should -Be 0
        }

        It 'resolves nested user-secrets: values from one listing' {
            Set-StoreFile 'nested'

            $result = resolve-value @{ A = 'user-secrets:Plain'; B = @{ C = 'user-secrets:Api:Key' } } -recurse -userSecretsId 'nested'

            $result.A | Should -Be 'value'
            $result.B.C | Should -Be 'a=b=c'
            $script:dotnetCalls.Count | Should -Be 1
        }
    }
}
