Describe "keyvault: value prefix registration" {
    BeforeEach {
        # Other test files swap the plugin list; start from the real plugins.
        InModuleScope ConfigMap {
            $script:savedPlugins = $script:ConfigMapPlugins
            $script:savedPrefixes = $script:ConfigMapValuePrefixes
            . "$PSScriptRoot\..\functions\plugins-init.ps1" -PluginsPath "$PSScriptRoot\..\plugins"
        }
    }

    AfterEach {
        InModuleScope ConfigMap {
            $script:ConfigMapPlugins = $script:savedPlugins
            $script:ConfigMapValuePrefixes = $script:savedPrefixes
        }
    }

    It "is registered by plugin-keyvault as a secret prefix" {
        InModuleScope ConfigMap {
            $prefix = Get-ConfigMapValuePrefix 'keyvault:'
            $prefix | Should -Not -BeNullOrEmpty
            $prefix.plugin.name | Should -Be 'keyvault'
            $prefix.secret | Should -BeTrue
        }
    }

    It "is not special-cased in core once the plugin is not registered" {
        InModuleScope ConfigMap {
            $script:ConfigMapValuePrefixes = @{}
            test-isSpecialValue 'keyvault:vault/name' | Should -BeFalse
            resolve-value 'keyvault:vault/name' | Should -Be 'keyvault:vault/name'
        }
    }

    It "masks keys filled from keyvault: in status output" {
        InModuleScope ConfigMap {
            $options = @{ prod = @{ A = 'keyvault:vault/name'; B = 'plain' } }
            Get-QConfSecretKey $options | Should -Be @('A')
        }
    }
}

Describe "keyvault: value resolution" {
    BeforeAll {
        . "$PSScriptRoot\..\functions\plugins.ps1"
        . "$PSScriptRoot\..\handlers\qconf\config-helpers.ps1"
        . "$PSScriptRoot\..\functions\plugins-init.ps1" -PluginsPath "$PSScriptRoot\..\plugins"
        # Standalone dot-sourcing has no module scope to lazy-load into: load the implementation directly.
        . "$PSScriptRoot\..\plugins\plugin-keyvault\keyvault.ps1"
        (Get-ConfigMapValuePrefix 'keyvault:').plugin.implementationLoaded = $true
    }

    It "treats keyvault: references as special" {
        test-isSpecialValue 'keyvault:vault/name' | Should -BeTrue
    }

    It "resolves vault and secret name through get-keyvaultSecret" {
        Mock get-keyvaultSecret { "secret-of-$vaultName-$secretName" }
        resolve-value 'keyvault:vault/name' | Should -Be 'secret-of-vault-name'
        Should -Invoke get-keyvaultSecret -Exactly 1 -ParameterFilter { $vaultName -eq 'vault' -and $secretName -eq 'name' }
    }

    It "keeps the literal when the secret cannot be retrieved" {
        Mock get-keyvaultSecret { $null }
        resolve-value 'keyvault:vault/name' | Should -Be 'keyvault:vault/name'
    }

    It "warns and returns null when az fails" {
        function az { $global:LASTEXITCODE = 1 }
        $out = get-keyvaultSecret 'vault' 'name' 3>&1
        "$out" | Should -Match "Failed to retrieve secret 'name' from vault 'vault'"
    }
}
