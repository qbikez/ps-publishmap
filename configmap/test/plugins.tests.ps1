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
