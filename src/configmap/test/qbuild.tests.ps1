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

Describe "qbuild passthrough args (--)" {
    BeforeAll {
        $script:capturedAdditionalArgs = $null
        function Invoke-CaptureAdditionalArgs {
            param($_context)
        }
        Mock Invoke-CaptureAdditionalArgs {
            param($_context)
            $script:capturedAdditionalArgs = $_context.additionalArgs
        }
        $script:passthroughTargets = @{
            "build" = {
                param($_context, [bool][switch]$noRestore)
                Invoke-CaptureAdditionalArgs @PSBoundParameters
            }
        }
    }

    BeforeEach {
        $script:capturedAdditionalArgs = $null
    }

    It "merges tokens after -- into _context.additionalArgs with order preserved" {
        qbuild -map $script:passthroughTargets "build" -- --config=Release --somethingelse
        Should -Invoke Invoke-CaptureAdditionalArgs -Times 1
        $script:capturedAdditionalArgs | Should -Be @('--config=Release', '--somethingelse')
    }

    It "merges tokens after known args" {
        qbuild -map $script:passthroughTargets "build" -NoRestore -- --config=Release --somethingelse
        Should -Invoke Invoke-CaptureAdditionalArgs -Times 1
        $script:capturedAdditionalArgs | Should -Be @('--config=Release', '--somethingelse')
    }

    It "does not populate additionalArgs when -- has no following tokens" {
        qbuild -map $script:passthroughTargets "build" --
        Should -Invoke Invoke-CaptureAdditionalArgs -Times 1
        $script:capturedAdditionalArgs | Should -BeNullOrEmpty
    }

    It "does not populate additionalArgs when none are there" {
        qbuild -map $script:passthroughTargets "build"
        Should -Invoke Invoke-CaptureAdditionalArgs -Times 1
        $script:capturedAdditionalArgs | Should -BeNullOrEmpty
    }

    It "does not populate additionalArgs with known args" {
        qbuild -map $script:passthroughTargets "build" -NoRestore
        Should -Invoke Invoke-CaptureAdditionalArgs -Times 1
        $script:capturedAdditionalArgs | Should -BeNullOrEmpty
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

Describe "parent without exec invoked without subcommand" {
    BeforeAll {
        Mock Write-Host

        $targets = @{
            "parent" = @{
                "child-one" = {
                    Write-Host "child-one executed"
                }
                "child-two" = {
                    Write-Host "child-two executed"
                }
            }
        }
    }

    It "should not execute any subcommand" {
        qbuild -map $targets "parent" -ErrorAction SilentlyContinue

        Should -Invoke Write-Host -Times 0 -ParameterFilter {
            $Object -eq "child-one executed"
        }
        Should -Invoke Write-Host -Times 0 -ParameterFilter {
            $Object -eq "child-two executed"
        }
    }

    It "should instruct the user to choose a subcommand" {
        qbuild -map $targets "parent" -ErrorAction SilentlyContinue

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match "(?i)subcommand|sub-command|choose|select|specify"
        }
    }

    It "should list the available subcommands" {
        qbuild -map $targets "parent" -ErrorAction SilentlyContinue

        Should -Invoke Write-Host -ParameterFilter {
            "$Object" -match "child-one"
        }
        Should -Invoke Write-Host -ParameterFilter {
            "$Object" -match "child-two"
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

Describe "qbuild !init" {
    BeforeAll {
        $testRoot = Join-Path $TestDrive "init-test"
        $parentDir = Join-Path $testRoot "parent"
        $childDir = Join-Path $parentDir "child"
        New-Item -ItemType Directory -Path $childDir -Force | Out-Null
    }

    It "should fail when map file already exists in current directory" {
        $existingDir = Join-Path $testRoot "existing"
        New-Item -ItemType Directory -Path $existingDir -Force | Out-Null
        "@{ 'test' = { Write-Host 'test' } }" | Out-File (Join-Path $existingDir ".build.map.ps1")

        Push-Location $existingDir
        try {
            { qbuild "!init" } | Should -Throw "*already exists*"
        }
        finally {
            Pop-Location
        }
    }

    It "should create map file even when parent directory has one" {
        # clean up any existing map files first
        Remove-Item (Join-Path $childDir ".build.map.ps1") -ErrorAction Ignore

        "@{ 'parent-cmd' = { Write-Host 'parent' } }" | Out-File (Join-Path $parentDir ".build.map.ps1")

        Push-Location $childDir
        try {
            # !init should create a new file regardless of parent's map
            qbuild "!init"
            # verify file was created in child
            Test-Path ".build.map.ps1" | Should -BeTrue
        }
        finally {
            Pop-Location
        }
    }

    It "should include !init in completions when no local map but parent has one" {
        # clean up any existing map files first
        Remove-Item (Join-Path $childDir ".build.map.ps1") -ErrorAction Ignore

        "@{ 'parent-cmd' = { Write-Host 'parent' } }" | Out-File (Join-Path $parentDir ".build.map.ps1")

        Push-Location $childDir
        try {
            # simulate tab completion
            $completer = (Get-Command qbuild).Parameters['entry'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
                Select-Object -First 1
            $completions = & $completer.ScriptBlock "qbuild" "entry" "" $null @{}

            $completions | Should -Contain "!init"
            $completions | Should -Contain "parent-cmd"
        }
        finally {
            Pop-Location
        }
    }

    It "should add npm entry with script subentries when package.json exists" {
        $npmDir = Join-Path $testRoot "npm-project"
        New-Item -ItemType Directory -Path $npmDir -Force | Out-Null
        Remove-Item (Join-Path $npmDir ".build.map.ps1") -ErrorAction Ignore
        @'
{"name":"test","version":"1.0.0","scripts":{"build":"echo build","test":"echo test","lint":"echo lint"}}
'@ | Out-File (Join-Path $npmDir "package.json") -Encoding utf8

        Push-Location $npmDir
        try {
            qbuild "!init"
            Test-Path ".build.map.ps1" | Should -BeTrue
            $content = Get-Content ".build.map.ps1" -Raw
            $content | Should -Match '"npm"\s*=\s*\[ordered\]@\{'
            $content | Should -Match '"build"\s*=\s*\{\s*npm run'
            $content | Should -Match '"test"\s*=\s*\{\s*npm run'
            $content | Should -Match '"lint"\s*=\s*\{\s*npm run'
            $map = . ".\.build.map.ps1"
            $map.Keys | Should -Contain "npm"
            $map.npm.build | Should -BeOfType [ScriptBlock]
            $map.npm.test | Should -BeOfType [ScriptBlock]
        }
        finally {
            Pop-Location
        }
    }
}