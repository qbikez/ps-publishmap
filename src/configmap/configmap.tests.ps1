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

    Describe '<name>' -ForEach @(
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
            Name    = "one-level simple list"
            Map     = [ordered]@{
                "key1" = @{
                    list = ("a", "b")
                }
                "key2" = @{ id = "b" }
            }
            Flatten = @("key1*", "a", "b", "key2")
            Tree    = @("key1.a", "key1.b", "key2")
        }
        @{
            Name    = "config-like"
            Map     = [ordered]@{
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
                    list = [ordered]@{
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
            Flatten = @("db", "secrets*", "connectionString", "keyVault")
            Tree    = @("db", "secrets.connectionString", "secrets.keyVault")
        }
    ) {
        It '<name> => flatten keys' {
            $list = (Get-CompletionList -map $map -flatten:$true)
            if (!$flatten) {
                $flatten = $keys
            }

            $list.Keys | Should -Be $Flatten
        }
        It '<name> => tree keys' {
            $list = (Get-CompletionList -map $map -flatten:$false)
            if (!$tree) {
                $tree = $keys
            }

            $list.Keys | Should -Be $Tree
        }
    }

    Describe "values" -ForEach @(
        @{
            Name   = "options value"
            Map    = @{
                options = [ordered]@{
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
                    return [ordered]@{
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
        function exec-mock($context) { "real" }
        Mock exec-mock { param($context) Write-Host $context }
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
            $entry = Get-MapEntry $map "build"

            Invoke-EntryCommand $entry "build" -context @{ a = 1 }
            Should -Invoke exec-mock
        }
    }
    Describe 'exec with args' -ForEach @(
        @{
            Name = "scriptblock with param"
            Map  = @{
                "build" = {
                    param($context)

                    exec-mock $context
                }
            }
        }
    ) {
        It "<name> => exec-mock" {
            $result = Get-CompletionList $map

            Invoke-EntryCommand $result.build -bound @{ context = @{ a = 1 } }
            Should -Invoke exec-mock -ParameterFilter {
                $context | Should -MatchObject @{ a = 1 }
                return $true
            }
        }
    }
}

Describe "qbuild" {
    BeforeAll {
        function Invoke-Build {
            param($ctx, [bool][switch]$noRestore)
        }
        Mock Invoke-Build {
            param($ctx, [bool][switch]$noRestore)

            $bound = $PSBoundParameters
            Write-Host "build script body"
            Write-Host "ctx=$($ctx | ConvertTo-Json)"
            Write-Host "noRestore=$noRestore"
            Write-Host "bound=$($bound | ConvertTo-Json)"
        }
        $targets = @{
            "build" = {
                param($ctx, [bool][switch]$noRestore)

                Invoke-Build @PSBoundParameters
            }
        }
    }

    Describe "script custom parameters" {
        It "should return parameters" {

            $parameters = Get-ScriptArgs $targets.build
            $parameters.Keys | Should -Be @("ctx", "noRestore")
        }

        It "should invoke with correct parameters" {
            qbuild -map $targets "build" -NoRestore
            Should -Invoke Invoke-Build -Times 1 -ParameterFilter { $noRestore -eq $true }
        }
    }
}


Describe "qconf" {
    BeforeAll {
        function Set-Conf {
            param($key, $value)
        }
        Mock Set-Conf
        $targets = @{
            "db" = @{
                options = { return [ordered]@{
                        "local"  = @{
                            "connectionString" = "localconnstr"
                        }
                        "remote" = @{
                            "connectionString" = "localconnstr"
                        }
                    }
                }
                set     = {
                    param($key, $value)

                    Set-Conf @PSBoundParameters
                }
                get     = {
                    return "my_value"
                }
            }
        }
    }

    Describe "set custom parameters" {
        It "should return parameters" {
            $parameters = Get-ScriptArgs $targets.db.set
            $parameters.Keys | Should -Be @("key", "value")
        }
        It "should return top-level completion list" {
            $list = Get-CompletionList $targets
            $list.Keys | Should -Be @("db")
        }
        It "should return options list" {
            $entry = Get-MapEntry $targets "db"
            $entry | Should -Not -BeNullOrEmpty
            $options = Get-CompletionList $entry -listKey "options"
            $options.Keys | Should -Be @("local", "remote")
        }
        It "invoke options" {
            $r = Invoke-EntryCommand $targets.db "options"
            $r.Keys | Should -Be @("local", "remote")
        }
        It "invoke get" {
            $r = Invoke-EntryCommand $targets.db "get"
            $r | Should -Be "my_value"
        }
        It "invoke set" {
            $r = Invoke-EntryCommand $targets.db "set" -bound @{ "key" = "key1"; "value" = "value2" }
            Should -Invoke Set-Conf -ParameterFilter { $key -eq "key1" -and $value -eq "value2" }
        }
    }
}

Describe "unified" {
    BeforeAll {

        Mock Write-Host

        $targets = @{
            "write:simple"  = {
                param([string] $message)

                Write-Host "SIMPLE: '$message'"
            }
            "write:wrapped" = @{
                exec  = {
                    param([string] $message)

                    Write-Host "WRAPPED: '$message'"
                }

                other = {
                    param([string] $message)

                    Write-Host "OTHER: '$message'"
                }
            }
            "write:custom"  = @{
                go = {
                    param([string] $message)
                    return "CUSTOM: '$message'"
                }
            }
            "write:getset"  = @{
                go  = {
                    param([string] $message)
                    return "GO: '$message'"
                }
                get = {
                    param([string] $message)
                    return "GET: '$message'"
                }
                set = {
                    param([string] $message)
                    Write-Host "SET: '$message'"
                }
            }

            "write:options" = {
                options = {
                    return @{
                        "option1" = "value1"
                        "option2" = "value2"
                    }
                }
                get = {
                    param([string] $message)
                    return "GET: '$message'"
                }
                set = {
                    param([string] $value, [string] $key)
                    Write-Host "SET: '$key' to '$value'"
                }
            }
        }
    }

    It "should write message with scriptblock" {
        qbuild -map $targets "write:simple" -message "Hello, World!"

        Should -Invoke Write-Host -Exactly 1 -ParameterFilter {
            $Object -eq "SIMPLE: 'Hello, World!'"
        }
    }

    It "should write message with wrapped scriptblock" {
        qbuild -map $targets "write:wrapped" -command "exec" -message "Hello, World!"

        Should -Invoke Write-Host -Exactly 1 -ParameterFilter {
            $Object -eq "WRAPPED: 'Hello, World!'"
        }
    }

    It "should handle ordered parameters" {
        qbuild -map $targets "write:wrapped" "exec" -message "Hello, World!"

        Should -Invoke Write-Host -Exactly 1 -ParameterFilter {
            $Object -eq "WRAPPED: 'Hello, World!'"
        }
    }
}