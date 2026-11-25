BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1
}

Describe "Invoke-ConfigMapPluginHooks priority" {
    It "invokes higher priority plugins first (lower number runs first)" {
        InModuleScope ConfigMap {
            $script:hookOrder = @()
            $script:ConfigMapPlugins = @(
                @{
                    name     = 'low'
                    priority = 50
                    hooks    = @{
                        TestHook = {
                            $script:hookOrder += 'low'
                            return @{ Handled = $true }
                        }
                    }
                },
                @{
                    name     = 'high'
                    priority = 10
                    hooks    = @{
                        TestHook = {
                            $script:hookOrder += 'high'
                            return @{ Handled = $false }
                        }
                    }
                }
            )

            Invoke-ConfigMapPluginHooks -HookName 'TestHook' -Context @{} | Out-Null

            $script:hookOrder | Should -Be @('high', 'low')
        }
    }

    It "defaults missing priority to lowest precedence" {
        InModuleScope ConfigMap {
            $script:hookOrder = @()
            $script:ConfigMapPlugins = @(
                @{
                    name  = 'default'
                    hooks = @{
                        TestHook = {
                            $script:hookOrder += 'default'
                            return @{ Handled = $true }
                        }
                    }
                },
                @{
                    name     = 'explicit'
                    priority = 1
                    hooks    = @{
                        TestHook = {
                            $script:hookOrder += 'explicit'
                            return @{ Handled = $false }
                        }
                    }
                }
            )

            Invoke-ConfigMapPluginHooks -HookName 'TestHook' -Context @{} | Out-Null

            $script:hookOrder | Should -Be @('explicit', 'default')
        }
    }
}

Describe "plugin value prefixes" {
    BeforeEach {
        $script:pluginsRoot = Join-Path $TestDrive 'plugins'
        $dir = Join-Path $script:pluginsRoot 'plugin-fake'
        New-Item -ItemType Directory $dir -Force | Out-Null
        Set-Content (Join-Path $dir 'fake.ps1') @'
$global:FakePluginLoads++
function script:get-fakeValue($ref) { if ($ref -eq 'missing') { return $null }; "fake-$ref" }
'@
        Set-Content (Join-Path $dir '_plugin.ps1') @'
@{
    name           = 'fake'
    implementation = 'fake.ps1'
    valuePrefixes  = @{
        'fake:' = @{ secret = $true; resolve = { param($Reference) get-fakeValue $Reference } }
    }
}
'@
        $global:FakePluginLoads = 0
        InModuleScope ConfigMap -Parameters @{ root = $script:pluginsRoot } {
            $script:savedPlugins = $script:ConfigMapPlugins
            $script:savedPrefixes = $script:ConfigMapValuePrefixes
            . "$PSScriptRoot\..\functions\plugins-init.ps1" -PluginsPath $root
        }
    }

    AfterEach {
        InModuleScope ConfigMap {
            $script:ConfigMapPlugins = $script:savedPlugins
            $script:ConfigMapValuePrefixes = $script:savedPrefixes
        }
        Remove-Variable FakePluginLoads -Scope Global -ErrorAction SilentlyContinue
    }

    It "registers prefixes without loading the implementation" {
        InModuleScope ConfigMap {
            test-isSpecialValue 'fake:thing' | Should -BeTrue
            test-isSpecialValue 'other:thing' | Should -BeFalse
            (Get-ConfigMapValuePrefix 'fake:').secret | Should -BeTrue
        }
        $global:FakePluginLoads | Should -Be 0
    }

    It "loads the implementation once, on first resolve" {
        InModuleScope ConfigMap {
            resolve-value 'fake:a' | Should -Be 'fake-a'
            resolve-value 'fake:b' | Should -Be 'fake-b'
        }
        $global:FakePluginLoads | Should -Be 1
    }

    It "keeps the literal when the plugin returns null" {
        InModuleScope ConfigMap {
            resolve-value 'fake:missing' | Should -Be 'fake:missing'
        }
    }

    It "warns and keeps the first plugin when a prefix is registered twice" {
        $dup = Join-Path $script:pluginsRoot 'plugin-dup'
        New-Item -ItemType Directory $dup -Force | Out-Null
        Set-Content (Join-Path $dup '_plugin.ps1') "@{ name='dup'; priority=200; valuePrefixes=@{ 'fake:' = @{ resolve = { 'dup' } } } }"
        InModuleScope ConfigMap -Parameters @{ root = $script:pluginsRoot } {
            . "$PSScriptRoot\..\functions\plugins-init.ps1" -PluginsPath $root 3>&1 | Should -Match "fake:"
            (Get-ConfigMapValuePrefix 'fake:').plugin.name | Should -Be 'fake'
        }
    }

    It "masks keys filled from secret prefixes in status output" {
        InModuleScope ConfigMap {
            $options = @{ prod = @{ A = 'fake:x'; B = 'plain' } }
            Get-QConfSecretKey $options | Should -Be @('A')
        }
    }
}
