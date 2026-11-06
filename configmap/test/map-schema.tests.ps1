BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1

    # The editor extension completes map keys from this file; it must not drift from the module.
    $script:schemaPath = Join-Path $PSScriptRoot '..\vscode-qbuild\src\mapSchema.json'
    $script:schema = Get-Content -LiteralPath $script:schemaPath -Raw | ConvertFrom-Json -AsHashtable
}

Describe 'qbuild map schema' {
    It 'describes every reserved build-map key' {
        $reserved = InModuleScope ConfigMap { (Get-MapLanguage build).reservedKeys }
        $described = @($schema.entryKeys.key) + @($schema.hiddenReservedKeys)

        @($described | Sort-Object) | Should -Be @($reserved | Sort-Object)
    }

    It 'lists every ConfigMap setting' {
        $names = InModuleScope ConfigMap { (New-ConfigMapSettings).PSObject.Properties.Name }

        @($schema.settings.key | Sort-Object) | Should -Be @($names | Sort-Object)
    }

    It 'lists only setting values the module accepts' {
        foreach ($setting in $schema.settings | Where-Object { $_.values }) {
            foreach ($value in $setting.values.value) {
                {
                    InModuleScope ConfigMap -Parameters @{ Key = $setting.key; Value = $value } {
                        param($Key, $Value)
                        New-ConfigMapSettings -Overrides @{ $Key = $Value }
                    }
                } | Should -Not -Throw -Because "$($setting.key) = '$value'"
            }
        }
    }

    It 'lists every registered process type' {
        $names = InModuleScope ConfigMap { $script:ConfigMapProcessHandlers.Keys }

        @($schema.processes.name | Sort-Object) | Should -Be @($names | Sort-Object)
    }

    It 'lists the legacy process aliases' {
        $aliases = InModuleScope ConfigMap { $script:ConfigMapProcessNameAliases }

        @($schema.processAliases.Keys | Sort-Object) | Should -Be @($aliases.Keys | Sort-Object)
        foreach ($alias in $aliases.Keys) {
            $schema.processAliases[$alias] | Should -Be $aliases[$alias]
        }
    }

    It 'restricts entry keys to known process types' {
        $known = @($schema.processes.name)
        foreach ($entryKey in $schema.entryKeys | Where-Object { $_.processes }) {
            $entryKey.processes | Where-Object { $_ -notin $known } | Should -BeNullOrEmpty -Because $entryKey.key
        }
    }

    It 'lists every _template type' {
        $types = InModuleScope ConfigMap { (Get-ConfigEntryTypeCommands).Keys }

        @($schema.templates.type | Sort-Object) | Should -Be @($types | Sort-Object)
    }

    It 'uses _template short forms the module parses' {
        foreach ($template in $schema.templates) {
            $parsed = InModuleScope ConfigMap -Parameters @{ Value = "$($template.shortForm):some/path" } {
                param($Value)
                Get-ConfigEntryTemplate -Entry @{ _template = $Value }
            }

            $parsed.type | Should -Be $template.type
            $parsed[$template.pathKey] | Should -Be 'some/path'
        }
    }
}
