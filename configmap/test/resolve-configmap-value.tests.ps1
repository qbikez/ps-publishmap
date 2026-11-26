BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force

    # Fake prefixes stand in for real plugins: `fake:` resolves (or not, for `missing*`) and
    # `ctx:` echoes the resolve context it was given.
    InModuleScope ConfigMap {
        $script:savedPrefixes = $script:ConfigMapValuePrefixes
        $script:ConfigMapValuePrefixes = @{
            'fake:' = @{
                plugin  = @{ name = 'fake' }
                secret  = $true
                resolve = {
                    param($Reference, $Context)
                    if ($Reference -like 'missing*') { Write-Warning "fake '$Reference' not found"; return $null }
                    "secret-$Reference"
                }
            }
            'ctx:'  = @{
                plugin  = @{ name = 'ctx' }
                resolve = { param($Reference, $Context) "$Reference|$($Context.Directory)|$($Context.UserSecretsId)" }
            }
        }
    }
}

AfterAll {
    InModuleScope ConfigMap { $script:ConfigMapValuePrefixes = $script:savedPrefixes }
}

Describe 'Resolve-ConfigMapValue' {
    It 'is exported from the module' {
        Get-Command Resolve-ConfigMapValue -Module ConfigMap | Should -Not -BeNullOrEmpty
    }

    It 'resolves a prefixed string' {
        Resolve-ConfigMapValue 'fake:api' | Should -Be 'secret-api'
    }

    It 'returns a plain string as is' {
        Resolve-ConfigMapValue 'plain text' | Should -Be 'plain text'
    }

    It 'accepts the value from the pipeline' {
        'fake:piped' | Resolve-ConfigMapValue | Should -Be 'secret-piped'
    }

    It 'passes Directory and UserSecretsId to the plugin context' {
        Resolve-ConfigMapValue 'ctx:key' -Directory 'some/dir' -UserSecretsId 'my-app' |
            Should -Be 'key|some/dir|my-app'
    }

    It 'rejects a value that is neither a string nor a dictionary' {
        { Resolve-ConfigMapValue @('fake:a', 'fake:b') } | Should -Throw '*string or a dictionary*'
    }

    Context 'dictionaries' {
        It 'resolves a hashtable recursively and keeps its keys' {
            $result = Resolve-ConfigMapValue @{
                A      = 'fake:one'
                B      = 'plain'
                Nested = @{ C = 'fake:two'; Deeper = @{ D = 'ctx:d' } }
                N      = 42
            } -UserSecretsId 'id-1'

            $result | Should -BeOfType [hashtable]
            @($result.Keys | Sort-Object) | Should -Be @('A', 'B', 'N', 'Nested')
            $result.A | Should -Be 'secret-one'
            $result.B | Should -Be 'plain'
            $result.N | Should -Be 42
            $result.Nested.C | Should -Be 'secret-two'
            $result.Nested.Deeper.D | Should -Be 'd||id-1'
        }

        It 'keeps an ordered dictionary ordered' {
            $result = Resolve-ConfigMapValue ([ordered]@{ z = 'fake:z'; a = 'fake:a'; m = 'plain' })

            $result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            @($result.Keys) | Should -Be @('z', 'a', 'm')
            $result.z | Should -Be 'secret-z'
        }

        It 'does not change the input' {
            $value = @{ A = 'fake:one'; Nested = @{ B = 'fake:two' } }

            Resolve-ConfigMapValue $value | Out-Null

            $value.A | Should -Be 'fake:one'
            $value.Nested.B | Should -Be 'fake:two'
        }

        It 'keeps an unresolved reference as the original string with a warning' {
            $result = Resolve-ConfigMapValue @{ A = 'fake:missing-a'; B = 'fake:b' } -WarningVariable warnings 3>$null

            $result.A | Should -Be 'fake:missing-a'
            $result.B | Should -Be 'secret-b'
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context '-Required' {
        It 'returns the resolved values when everything resolves' {
            $result = Resolve-ConfigMapValue @{ A = 'fake:a'; B = 'plain' } -Required

            $result.A | Should -Be 'secret-a'
        }

        It 'throws for an unresolved string and names the reference' {
            { Resolve-ConfigMapValue 'fake:missing-top' -Required 3>$null } |
                Should -Throw '*fake:missing-top*'
        }

        It 'names every failed key and reference, without the resolved secret values' {
            $value = [ordered]@{
                OK     = 'fake:ok'
                Bad    = 'fake:missing-bad'
                Nested = @{ Inner = 'fake:missing-inner'; Fine = 'fake:fine' }
                Empty  = $null
            }

            $err = $null
            try { Resolve-ConfigMapValue $value -Required 3>$null }
            catch { $err = $_ }

            $err | Should -Not -BeNullOrEmpty
            $message = $err.Exception.Message
            $message | Should -Match 'Bad: fake:missing-bad'
            $message | Should -Match 'Nested\.Inner: fake:missing-inner'
            $message | Should -Match 'Empty: null'
            $message | Should -Not -Match 'secret-'
            $message | Should -Not -Match 'OK'
        }

        It 'throws when a value resolves to null' {
            Mock get-keyvaultSecret -ModuleName ConfigMap { $null }

            { Resolve-ConfigMapValue @{ Conn = 'keyvault:vault/conn' } -Required 3>$null } |
                Should -Throw '*Conn: keyvault:vault/conn*'
        }
    }

    It 'resolves values from a map scriptblock' {
        $mapFile = Join-Path $TestDrive '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{ secret = { Resolve-ConfigMapValue "fake:from-map" -Required } }'

        $map = Import-ConfigMap -Map $mapFile

        & $map.secret.exec | Should -Be 'secret-from-map'
    }
}
