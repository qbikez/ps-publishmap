BeforeDiscovery {
    function Should-MatchObject ($ActualValue, [hashtable]$ExpectedValue, [switch] $Negate, [string] $Because) {
        <#
        .SYNOPSIS
            Asserts if hashtable/objects contains the same keys and values
        .EXAMPLE
            @{ a = 1 } | Should -MatchObject @{ a = 1 }
    
            Checks if object matches the other one. This will pass.
    
        .EXAMPLE
            @{ a = 1, b = 2 } | Should -MatchObject @{ a = 1 }
    
            Checks if object matches the other one. Additional keys on the actual value are ignored.
        #>
    
        $diff = [ordered]@{}
        foreach ($kvp in $ExpectedValue.GetEnumerator()) {
            $key = $kvp.Key
            $actual = $ActualValue.$key
            $expected = $kvp.Value
            if ($actual -ne $expected) {
                $diff["-$key"] = $expected
                $diff["+$key"] = $actual
            }
        }

        if ($Negate) {
            if ($diff.Count -gt 0) {
                return [pscustomobject]@{
                    Succeeded      = $true
                    FailureMessage = $null
                }
            }
            else {
                return [pscustomobject]@{
                    Succeeded      = $false
                    FailureMessage = "Expected object to not match $($actual | ConvertTo-Json). $Because"
                }
            }
        }
        else {
            if ($diff.Count -eq 0) {
                return [pscustomobject]@{
                    Succeeded      = $true
                    FailureMessage = $null
                }
            }
            else {
                return [pscustomobject]@{
                    Succeeded      = $false
                    FailureMessage = "Expected objects to match. Diff: $($diff | ConvertTo-Json). $Because"
                }
            }
        }
    }
    
    Add-ShouldOperator -Name MatchObject `
        -InternalName 'Should-MatchObject' `
        -Test ${function:Should-MatchObject} `
        -SupportsArrayInput
}
BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\configmap.psm1
}

Describe "map parsing" {

    Describe 'keys' -ForEach @(
        @{
            Name = "simple list"
            Map  = @("item1", "item2")
            Keys = @("item1", "item2")
        }
        @{
            Name = "simple map"
            Map  = [ordered]@{
                "key1" = @{ id = "a" }
                "key2" = @{ id = "b" }
            }
            Keys = @("key1", "key2")
        }
        @{
            Name = "one-level simple list"
            Map  = [ordered]@{
                "key1" = @{
                    list = ("a", "b")
                }
                "key2" = @{ id = "b" }
            }
            Keys = @("key1*", "a", "b", "key2")
        }
        @{
            Name = "config-like"
            Map  = [ordered]@{
                "db"      = @{
                    options = @{
                        "local"  = @{
                            connectionString = "blah"
                        }
                        "remote" = @{
                            connectionString = "boom"
                        }
                    }
                }
                "secrets" = @{
                    list = @{
                        connectionString = @{
                            "local"  = "blah"
                            "remote" = "boom"
                        }
                        keyVault         = @{
                            "local"  = "blah"
                            "remote" = "boom"
                        }
                    }
                }
            }
            Keys = @("db", "secrets*", "connectionString", "keyVault")
        }
    ) {
        Describe "<name>" {
            It '<name> => keys' {
                $result = Get-CompletionList $map
                $result.Keys | Should -Be $keys
            }
        }
    }

    Describe "values" -ForEach @(
        @{
            Name   = "options value"
            Map    = @{
                options = @{
                    "a" = 1
                    "b" = 2
                }
            }
            Values = @("a", "b")
        }
        @{
            Name   = "options func"
            Map    = @{
                options = {
                    return @{
                        "a" = 1
                        "b" = 2
                    }
                }
            }
            Values = @("a", "b")
        }
    ) {
        Describe "<name>" {
            It "<name> => options" {
                $result = Get-ValuesList $map
                $result.Keys | Should -Be $Values
            }
        }
    }
}

Describe "map execuction" {
    BeforeEach {
        function exec-mock($ctx) { "real" }
        Mock exec-mock { param($ctx) write-host $ctx }
    }
    Describe 'exec without args' -ForEach @(
        @{
            Name = "simple scriptblock"
            Map  = @{
                "build" = {
                    exec-mock
                }
            }
        }
    ) {
        It "<name> => exec-mock without args" {
            $result = Get-CompletionList $map

            Invoke-ModuleCommand $result "build" -context @{ a = 1 }
            Should -Invoke exec-mock
        }
    }
    Describe 'exec with args' -ForEach @(
        @{
            Name = "scriptblock with param"
            Map  = @{
                "build" = {
                    param($ctx)

                    exec-mock $ctx
                }
            }
        }
    ) {
        It "<name> => exec-mock" {
            $result = Get-CompletionList $map

            Invoke-ModuleCommand $result "build" -context @{ a = 1 }
            Should -Invoke exec-mock -ParameterFilter {
                $ctx | Should -MatchObject @{ a = 1 }
                return $true
            }
        }
    }
}