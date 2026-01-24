BeforeDiscovery {
    . "$PSScriptRoot\test-utils.ps1"
}
BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1
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

Describe "qbuild dynamic parameters" {
    BeforeAll {
        Mock Write-Host
        
        $buildTargets = @{
            "push:short" = {
                param([switch]$NewVersion, [string]$path = $null)
                    
                Write-Host "Running push/publish workflow with args: NewVersion=$NewVersion, path=$path"
            }
            
            "push:exec"  = @{
                exec        = {
                    param([switch]$NewVersion, [string]$path = $null)
                    
                    Write-Host "Running push/publish workflow with args: NewVersion=$NewVersion, path=$path"
                }
                description = "Push/publish module (runs tests first)"
            }
        }
    }

    It "should recognize <EntryType> command parameters" -TestCases @(
        @{ EntryType = "push:short"; }
        @{ EntryType = "push:exec"; }
    ) {
        param($EntryType)
        $entry = Get-MapEntry $buildTargets $EntryType
        $scriptBlock = Get-EntryCommand $entry

        $parameters = Get-ScriptArgs $ScriptBlock
        $parameters.Keys | Should -Contain "NewVersion"
        $parameters.Keys | Should -Contain "path"
    }

    It "should handle <EntryType> command with -path parameter" -TestCases @(
        @{ EntryType = "push:short" }
        @{ EntryType = "push:exec" }
    ) {
        param($EntryType)
        
        qbuild -map $buildTargets $EntryType -path ".\src\configmap\"

        Should -Invoke Write-Host -ParameterFilter {
            $Object -eq "Running push/publish workflow with args: NewVersion=False, path=.\src\configmap\"
        }
    }

    It "should handle <EntryType> command with -NewVersion and -path parameters" -TestCases @(
        @{ EntryType = "push:short" }
        @{ EntryType = "push:exec" }
    ) {
        param($EntryType)
        
        qbuild -map $buildTargets $EntryType -NewVersion -path ".\src\configmap\"

        Should -Invoke Write-Host -ParameterFilter {
            $Object -eq "Running push/publish workflow with args: NewVersion=True, path=.\src\configmap\"
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

Describe "hierarchical" {
    BeforeAll {

        Mock Write-Host

        $targets = @{
            "parent" = @{
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
    }
 
    It "should write message with scriptblock" {
        qbuild -map $targets "parent.write:simple" -message "Hello, World!"

        Should -Invoke Write-Host -Exactly 1 -ParameterFilter {
            $Object -eq "SIMPLE: 'Hello, World!'"
        }
    }
}

Describe "hierarchical completion" {
    BeforeAll {
        $targets = @{
            "parent"  = @{
                "write:simple"  = {
                    param([string] $message)
                    Write-Host "SIMPLE: '$message'"
                }
                "write:wrapped" = @{
                    exec = {
                        param([string] $message)
                        Write-Host "WRAPPED: '$message'"
                    }
                }
                "other:command" = {
                    Write-Host "Other command"
                }
            }
            "regular" = {
                Write-Host "Regular command"
            }
            "another" = @{
                "nested:cmd" = {
                    Write-Host "Nested command"
                }
            }
        }
    }

    It "should complete partial parent name 'paren' to show all parent.* commands" {
        $completions = Get-EntryCompletion -map $targets -language build -wordToComplete "paren" @{}
        
        $completions | Should -Contain "parent.write:simple"
        $completions | Should -Contain "parent.write:wrapped" 
        $completions | Should -Contain "parent.other:command"
        $completions | Should -Contain "parent*"
    }

    It "should complete 'parent.' to show all parent child commands" {
        $completions = Get-EntryCompletion -map $targets -language build -wordToComplete "parent." @{}
        
        $completions | Should -Contain "parent.write:simple"
        $completions | Should -Contain "parent.write:wrapped"
        $completions | Should -Contain "parent.other:command"
        $completions | Should -Not -Contain "regular"
        $completions | Should -Not -Contain "another.nested:cmd"
    }

    It "should complete 'parent.write' to show only matching write commands" {
        $completions = Get-EntryCompletion -map $targets -language build -wordToComplete "parent.write" @{}
        
        $completions | Should -Contain "parent.write:simple"
        $completions | Should -Contain "parent.write:wrapped"
        $completions | Should -Not -Contain "parent.other:command"
        $completions | Should -Not -Contain "regular"
    }

    It "should complete regular commands normally" {
        $completions = Get-EntryCompletion -map $targets -language build -wordToComplete "reg" @{}
        
        $completions | Should -Contain "regular"
        $completions | Should -Not -Contain "parent.write:simple"
    }

    It "should complete partial parent names to multiple parent groups" {
        $completions = Get-EntryCompletion -map $targets -language build -wordToComplete "" @{}
        
        $completions | Should -Contain "parent.write:simple"
        $completions | Should -Contain "another.nested:cmd"
        $completions | Should -Contain "regular"
        $completions | Should -Contain "parent*"
        $completions | Should -Contain "another*"
    }

    It "should handle empty completion to show all available commands" {
        $completions = Get-EntryCompletion -map $targets -language build -wordToComplete "" @{}
        
        # Should contain both hierarchical and flat commands
        $completions.Count | Should -BeGreaterThan 5
        $completions | Should -Contain "regular"
        $completions | Should -Contain "parent.write:simple"
        $completions | Should -Contain "another.nested:cmd"
    }
}