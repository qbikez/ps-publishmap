BeforeDiscovery {
    . "$PSScriptRoot\test-utils.ps1"
}
BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\configmap.psm1
}

Describe "Test-IsParentEntry" {
    It "should identify scriptblock as leaf" {
        $entry = { Write-Host "Command" }
        $result = Test-IsParentEntry $entry
        $result.IsParent | Should -Be $false
        $result.HasExplicitList | Should -Be $false
    }

    It "should identify command object with exec as leaf" {
        $entry = @{
            exec = { Write-Host "Command" }
            description = "A command"
        }
        $result = Test-IsParentEntry $entry
        $result.IsParent | Should -Be $false
        $result.HasExplicitList | Should -Be $false
    }

    It "should identify explicit list as parent" {
        $entry = @{
            list = @{
                "cmd1" = { Write-Host "Command 1" }
                "cmd2" = { Write-Host "Command 2" }
            }
        }
        $result = Test-IsParentEntry $entry
        $result.IsParent | Should -Be $true
        $result.HasExplicitList | Should -Be $true
    }

    It "should identify direct nested structure as parent" {
        $entry = @{
            "subcmd1" = { Write-Host "Sub command 1" }
            "subcmd2" = @{
                exec = { Write-Host "Sub command 2" }
            }
        }
        $result = Test-IsParentEntry $entry
        $result.IsParent | Should -Be $true
        $result.HasExplicitList | Should -Be $false
    }

    It "should identify data object as leaf" {
        $entry = @{
            name = "test"
            value = 42
            items = @("a", "b", "c")
        }
        $result = Test-IsParentEntry $entry
        $result.IsParent | Should -Be $false
        $result.HasExplicitList | Should -Be $false
    }

    It "should identify mixed command object as parent when exec and subcommand is present" {
        $entry = @{
            exec = { Write-Host "Main command" }
            "subcmd" = { Write-Host "This should not make it a parent" }
        }
        $result = Test-IsParentEntry $entry
        $result.IsParent | Should -Be $true
        $result.HasExplicitList | Should -Be $false
    }
}

Describe "hierarchical key functions" {
    Describe "Test-IsHierarchicalKey" {
        It "should identify hierarchical key with default separator" {
            Test-IsHierarchicalKey "parent.child" | Should -Be $true
        }

        It "should identify non-hierarchical key" {
            Test-IsHierarchicalKey "simple" | Should -Be $false
        }

        It "should handle custom separator" {
            Test-IsHierarchicalKey "parent/child" "/" | Should -Be $true
            Test-IsHierarchicalKey "parent.child" "/" | Should -Be $false
        }

        It "should handle empty or null keys" {
            Test-IsHierarchicalKey "" | Should -Be $false
            Test-IsHierarchicalKey $null | Should -Be $false
        }

        It "should identify deep hierarchical keys" {
            Test-IsHierarchicalKey "level1.level2.level3.level4.level5" | Should -Be $true
            Test-IsHierarchicalKey "a.b.c.d.e.f.g.h.i.j" | Should -Be $true
        }
    }

    Describe "Split-HierarchicalKey" {
        It "should split key with default separator" {
            $parts = Split-HierarchicalKey "parent.child.grandchild"
            $parts | Should -Be @("parent", "child", "grandchild")
        }

        It "should split key with custom separator" {
            $parts = Split-HierarchicalKey "parent/child/grandchild" "/"
            $parts | Should -Be @("parent", "child", "grandchild")
        }

        It "should handle single part key" {
            $parts = Split-HierarchicalKey "simple"
            $parts | Should -Be @("simple")
        }

        It "should handle empty key" {
            $parts = Split-HierarchicalKey ""
            $parts | Should -Be @()
        }

        It "should handle special regex characters in separator" {
            $parts = Split-HierarchicalKey "parent*child*grandchild" "*"
            $parts | Should -Be @("parent", "child", "grandchild")
        }

        It "should split deep hierarchical keys" {
            $parts = Split-HierarchicalKey "level1.level2.level3.level4.level5"
            $parts | Should -Be @("level1", "level2", "level3", "level4", "level5")
        }

        It "should split very deep hierarchical keys" {
            $parts = Split-HierarchicalKey "a.b.c.d.e.f.g.h.i.j"
            $parts | Should -Be @("a", "b", "c", "d", "e", "f", "g", "h", "i", "j")
        }
    }

    Describe "Resolve-HierarchicalPath" {
        BeforeAll {
            $testMap = @{
                "parent" = @{
                    "child" = @{
                        "grandchild" = "found"
                    }
                    "simple" = "parent-simple"
                }
                "root" = "root-value"
            }
        }

        It "should resolve deep hierarchical path" {
            $result = Resolve-HierarchicalPath $testMap "parent.child.grandchild"
            $result | Should -Be "found"
        }

        It "should resolve shallow hierarchical path" {
            $result = Resolve-HierarchicalPath $testMap "parent.simple"
            $result | Should -Be "parent-simple"
        }

        It "should return null for non-hierarchical key" {
            $result = Resolve-HierarchicalPath $testMap "root"
            $result | Should -Be $null
        }

        It "should return null for non-existent path" {
            $result = Resolve-HierarchicalPath $testMap "parent.nonexistent"
            $result | Should -Be $null
        }

        It "should handle custom separator" {
            $customMap = @{
                "parent" = @{
                    "child" = @{
                        "grandchild" = "found-with-slash"
                    }
                }
            }
            # Test with correct custom separator
            $result = Resolve-HierarchicalPath $customMap "parent/child/grandchild" "/"
            $result | Should -Be "found-with-slash"
            
            # Test with wrong separator (should return null because not identified as hierarchical)
            $result2 = Resolve-HierarchicalPath $customMap "parent.child.grandchild" "/"
            $result2 | Should -Be $null
        }

        It "should return intermediate objects" {
            $result = Resolve-HierarchicalPath $testMap "parent.child"
            $result | Should -Not -Be $null
            $result.grandchild | Should -Be "found"
        }

        It "should resolve deep hierarchical paths" {
            $deepMap = @{
                "level1" = @{
                    "level2" = @{
                        "level3" = @{
                            "level4" = @{
                                "level5" = @{
                                    "command" = "deep-command"
                                }
                            }
                        }
                    }
                }
            }
            
            $result = Resolve-HierarchicalPath $deepMap "level1.level2.level3.level4.level5.command"
            $result | Should -Be "deep-command"
        }

        It "should resolve very deep hierarchical paths (10 levels)" {
            $veryDeepMap = @{
                "a" = @{
                    "b" = @{
                        "c" = @{
                            "d" = @{
                                "e" = @{
                                    "f" = @{
                                        "g" = @{
                                            "h" = @{
                                                "i" = @{
                                                    "j" = "very-deep-command"
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            $result = Resolve-HierarchicalPath $veryDeepMap "a.b.c.d.e.f.g.h.i.j"
            $result | Should -Be "very-deep-command"
        }

        It "should return null for broken deep paths" {
            $deepMap = @{
                "level1" = @{
                    "level2" = @{
                        "level3" = @{
                            "level4" = "terminal-value"
                        }
                    }
                }
            }
            
            $result = Resolve-HierarchicalPath $deepMap "level1.level2.level3.level4.level5"
            $result | Should -Be $null
        }
    }
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
        @{
            Name    = "deep nesting (5 levels)"
            Map     = [ordered]@{
                "level1" = @{
                    "level2" = @{
                        "level3" = @{
                            "level4" = @{
                                "level5" = @{
                                    exec = { Write-Host "Deep command" }
                                }
                                "another5" = { Write-Host "Another deep" }
                            }
                            "alt4" = { Write-Host "Alternative path" }
                        }
                    }
                }
                "simple" = { Write-Host "Simple command" }
            }
            Flatten = @("level1*", "level2*", "level3*", "level4*", "level5", "another5", "alt4", "simple")
            Tree    = @("level1.level2.level3.level4.level5", "level1.level2.level3.level4.another5", "level1.level2.level3.alt4", "simple")
        }
        @{
            Name    = "very deep nesting (10 levels)"
            Map     = [ordered]@{
                "a" = @{
                    "b" = @{
                        "c" = @{
                            "d" = @{
                                "e" = @{
                                    "f" = @{
                                        "g" = @{
                                            "h" = @{
                                                "i" = @{
                                                    "j" = { Write-Host "Very deep command" }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                "root" = { Write-Host "Root command" }
            }
            Flatten = @("a*", "b*", "c*", "d*", "e*", "f*", "g*", "h*", "i*", "j", "root")
            Tree    = @("a.b.c.d.e.f.g.h.i.j", "root")
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
        function exec-mock($_context) { "real" }
        Mock exec-mock { param($_context) Write-Host $_context }
    }
    Describe 'exec without args' -ForEach @(
        @{
            Name = "simple scriptblock"
            Map  = @{
                "build" = {
                    param($_context)
                    exec-mock
                }
            }
        }
    ) {
        It "<name> => exec-mock without args" {
            $entry = Get-MapEntry $map "build"
            $s = Get-EntryCommand $entry
            $p = Get-ScriptArgs $s

            Invoke-EntryCommand $entry "build" -context @{ a = 1 }
            Should -Invoke exec-mock
        }
    }
    Describe 'exec with args' -ForEach @(
        @{
            Name = "scriptblock with param"
            Map  = @{
                "build" = {
                    param($_context)

                    exec-mock $_context
                }
            }
        }
    ) {
        It "<name> => exec-mock" {
            $result = Get-CompletionList $map

            Invoke-EntryCommand $result.build -bound @{ _context = @{ a = 1 } }
            Should -Invoke exec-mock -ParameterFilter {
                $_context | Should -MatchObject @{ a = 1 }
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
        @{ EntryType = "push:short";  }
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

Describe "deep hierarchical execution" {
    BeforeEach {
        Mock Write-Host
    }

    Describe "deep nesting commands" {
        BeforeAll {
            $deepMap = @{
                "level1" = @{
                    "level2" = @{
                        "level3" = @{
                            "level4" = @{
                                "level5" = {
                                    param([string]$message = "default")
                                    Write-Host "Deep level 5: $message"
                                }
                            }
                        }
                    }
                }
                "root" = {
                    Write-Host "Root command"
                }
            }
        }

        It "should execute deep hierarchical commands" {
            qbuild -map $deepMap "level1.level2.level3.level4.level5" -message "test"
            
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter {
                $Object -eq "Deep level 5: test"
            }
        }

        It "should get deep hierarchical entry" {
            $entry = Get-MapEntry $deepMap "level1.level2.level3.level4.level5"
            $entry | Should -Not -BeNullOrEmpty
            $entry | Should -BeOfType [ScriptBlock]
        }

        It "should extract parameters from deep commands" {
            $entry = Get-MapEntry $deepMap "level1.level2.level3.level4.level5"
            $parameters = Get-ScriptArgs $entry
            $parameters.Keys | Should -Contain "message"
        }
    }

    Describe "very deep nesting commands (10 levels)" {
        BeforeAll {
            $veryDeepMap = @{
                "a" = @{
                    "b" = @{
                        "c" = @{
                            "d" = @{
                                "e" = @{
                                    "f" = @{
                                        "g" = @{
                                            "h" = @{
                                                "i" = @{
                                                    "j" = {
                                                        param([string]$message = "deep", [int]$count = 1)
                                                        Write-Host "Very deep command: message=$message, count=$count"
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        It "should execute very deep hierarchical commands" {
            qbuild -map $veryDeepMap "a.b.c.d.e.f.g.h.i.j" -message "test" -count 5
            
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter {
                $Object -eq "Very deep command: message=test, count=5"
            }
        }

        It "should get very deep hierarchical entry" {
            $entry = Get-MapEntry $veryDeepMap "a.b.c.d.e.f.g.h.i.j"
            $entry | Should -Not -BeNullOrEmpty
            $entry | Should -BeOfType [ScriptBlock]
        }

        It "should extract parameters from very deep commands" {
            $entry = Get-MapEntry $veryDeepMap "a.b.c.d.e.f.g.h.i.j"
            $parameters = Get-ScriptArgs $entry
            $parameters.Keys | Should -Contain "message"
            $parameters.Keys | Should -Contain "count"
        }
    }

    Describe "mixed depth hierarchical commands" {
        BeforeAll {
            $mixedMap = [ordered]@{
                "build" = { 
                    Write-Host "build command" 
                }
                "build:exec" = [ordered]@{
                    exec = { 
                        Write-Host "build:exec command" 
                    }
                    description = "Build command"
                }
                "db" = [ordered]@{
                    exec = {
                        write-host "db top-level exec"
                    }
                    "migrate" = {
                        Write-Host "db.migrate command"
                    }
                    "migrate:exec" = [ordered]@{
                        exec = {
                            Write-Host "db.migrate:exec command"
                        }
                        description = "Migrate command"
                    }
                    "init" = {
                        Write-Host "db.init command"
                    }
                    "init:exec" = [ordered]@{
                        exec = {
                            Write-Host "db.init:exec command"
                        }
                    }
                }                
            }
        }

        It "should return expected completionlist" {
            $flatList = Get-CompletionList $mixedMap -flatten:$false
            $flatList.Keys | Should -Be @(
                "build"
                "build:exec"
                "db.migrate"
                "db.migrate:exec"
                "db.init"
                "db.init:exec"
            )
        }

        # It "should handle mixed depth commands in tree completion" {
        #     $treeList = Get-CompletionList $mixedMap -flatten:$false
        #     $treeList.Keys | Should -Contain "shallow"
        #     $treeList.Keys | Should -Contain "medium.sub"
        #     $treeList.Keys | Should -Contain "deep.level2.level3.level4.level5"
        # }

        # It "should execute shallow command" {
        #     qbuild -map $mixedMap "shallow"
        #     Should -Invoke Write-Host -ParameterFilter { $Object -eq "Shallow command" }
        # }

        # It "should execute medium depth command" {
        #     qbuild -map $mixedMap "medium.sub"
        #     Should -Invoke Write-Host -ParameterFilter { $Object -eq "Medium depth command" }
        # }

        # It "should execute deep command" {
        #     qbuild -map $mixedMap "deep.level2.level3.level4.level5"
        #     Should -Invoke Write-Host -ParameterFilter { $Object -eq "Deep command" }
        # }
    }
}

Describe "custom commands" {
    BeforeAll {
        Mock Write-Host

        $mixedMap = [ordered]@{
            "db" = [ordered]@{ 
                init = {
                    write-host "db init"
                }
                migrate = [ordered]@{
                    exec = {
                        write-host "db migrate"
                    }
                    description = "Migrate command"
                }
            }             
        }
    }

    It "should return expected completionlist" {
        $flatList = Get-CompletionList $mixedMap -flatten:$false
        $flatList.Keys | Should -Be @(
            "db.init"
            "db.migrate"
        )
    }

    It "should return expected entries" {
        $entries = Get-MapEntries $mixedMap "db.init"
        $entries.Count | Should -Be 1
        $entries[0].Key | Should -Be "db.init"
        $entries[0].Value | Should -BeOfType [ScriptBlock]
    }

    It "should execute custom command" {
        qbuild -map $mixedMap "db.init"
        Should -Invoke Write-Host -ParameterFilter { $Object -eq "db init" }
    }

    It "should execute custom command with exec" {
        qbuild -map $mixedMap "db.migrate"
        Should -Invoke Write-Host -ParameterFilter { $Object -eq "db migrate" }
    }

    Describe "entry as submap" {
        BeforeAll {
            $entry = get-mapentry $mixedMap "db"
            $entry | Should -Not -BeNullOrEmpty
            $entry | Should -BeOfType [System.Collections.IDictionary]
        }

        It "should return expected completionlist" {
            $flatList = Get-CompletionList $entry -flatten:$false
            $flatList.Keys | Should -Be @(
                "init"
                "migrate"
            )
        }

        It "should execute custom command" {
            qbuild -map $entry "init"
            Should -Invoke Write-Host -ParameterFilter { $Object -eq "db init" }
        }
    }
}