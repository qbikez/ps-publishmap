BeforeAll {
    . "$PSScriptRoot\..\functions\plugins.ps1"
    . "$PSScriptRoot\..\handlers\qconf\config-helpers.ps1"
    . "$PSScriptRoot\..\functions\plugins-init.ps1" -PluginsPath "$PSScriptRoot\..\plugins"
    # Standalone dot-sourcing has no module scope to lazy-load into: load the implementation directly.
    . "$PSScriptRoot\..\plugins\plugin-bw\bw.ps1"
    (Get-ConfigMapValuePrefix 'bw:').plugin.implementationLoaded = $true
}

Describe "bw: value prefix" {
    Context "test-isSpecialValue" {
        It "treats bw: references as special" {
            test-isSpecialValue 'bw:my-login' | Should -BeTrue
        }

        It "does not treat lookalikes as special" {
            test-isSpecialValue 'bwx' | Should -BeFalse
            test-isSpecialValue 'BW:my-login' | Should -BeFalse
        }
    }

    Context "resolve-value" {
        BeforeEach {
            Mock get-bwSecret { "secret-of-$item" }
        }

        It "resolves a bare item as its password" {
            resolve-value 'bw:my-login' | Should -Be 'secret-of-my-login'
            Should -Invoke get-bwSecret -Exactly 1 -ParameterFilter { $item -eq 'my-login' -and -not $field }
        }

        It "splits item and field on the first slash" {
            resolve-value 'bw:my login/username' | Should -Be 'secret-of-my login'
            Should -Invoke get-bwSecret -Exactly 1 -ParameterFilter { $item -eq 'my login' -and $field -eq 'username' }
        }

        It "keeps further slashes in the field name" {
            resolve-value 'bw:item/api/key' | Out-Null
            Should -Invoke get-bwSecret -Exactly 1 -ParameterFilter { $item -eq 'item' -and $field -eq 'api/key' }
        }

        It "warns and keeps the literal when the lookup fails" {
            Mock get-bwSecret { $null }
            resolve-value 'bw:missing' 3>$null | Should -Be 'bw:missing'
        }

        It "resolves nested values with -recurse" {
            $result = resolve-value @{ a = 'bw:one'; b = 'plain' } -recurse
            $result.a | Should -Be 'secret-of-one'
            $result.b | Should -Be 'plain'
        }
    }

    Context "get-bwSecret" {
        BeforeAll {
            function bw {
                $script:bwCalls += , @($args)
                $global:LASTEXITCODE = $script:bwExit
                $script:bwOutput
            }
        }

        BeforeEach {
            $script:bwCalls = @()
            $script:bwExit = 0
            $script:bwOutput = 'value'
        }

        It "reads the password when no field is given" {
            get-bwSecret 'item-pw' $null | Should -Be 'value'
            $script:bwCalls[0] | Should -Be @('get', 'password', 'item-pw', '--nointeraction')
        }

        It "maps well-known fields to bw get <field>" {
            get-bwSecret 'item-user' 'username' | Should -Be 'value'
            $script:bwCalls[0] | Should -Be @('get', 'username', 'item-user', '--nointeraction')
        }

        It "reads a custom field from the item json" {
            $script:bwOutput = '{"fields":[{"name":"apikey","value":"k-123"},{"name":"other","value":"x"}]}'
            get-bwSecret 'item-custom' 'apikey' | Should -Be 'k-123'
            $script:bwCalls[0] | Should -Be @('get', 'item', 'item-custom', '--nointeraction')
        }

        It "warns and returns null when the custom field is missing" {
            $script:bwOutput = '{"fields":[]}'
            $out = get-bwSecret 'item-nofield' 'nope' 3>&1
            @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 1
            $out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] } | Should -BeNullOrEmpty
        }

        It "warns without leaking the secret and returns null when bw fails" {
            $script:bwExit = 1
            $script:bwOutput = 'super-secret-leak'
            $out = get-bwSecret 'item-fail' $null 3>&1
            $result = @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $result.Count | Should -Be 1
            "$result" | Should -Match 'bw unlock'
            "$result" | Should -Not -Match 'super-secret-leak'
        }

        It "does not call bw twice for the same reference" {
            get-bwSecret 'item-cache' 'username' | Out-Null
            get-bwSecret 'item-cache' 'username' | Should -Be 'value'
            $script:bwCalls.Count | Should -Be 1
        }

        It "does not cache failures" {
            $script:bwExit = 1
            get-bwSecret 'item-retry' $null 3>$null | Should -BeNullOrEmpty
            $script:bwExit = 0
            get-bwSecret 'item-retry' $null | Should -Be 'value'
        }
    }
}
