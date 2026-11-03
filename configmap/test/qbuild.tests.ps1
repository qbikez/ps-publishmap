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

Describe "qbuild multi-target" {
    BeforeAll {
        $script:mtRan = [System.Collections.Generic.List[string]]::new()
        function Invoke-MTTarget { param([string]$name) }
        Mock Invoke-MTTarget { param([string]$name) $script:mtRan.Add($name) }
        $script:mtTargets = @{
            "clean" = { Invoke-MTTarget -name "clean" }
            "build" = { Invoke-MTTarget -name "build" }
            "test"  = { Invoke-MTTarget -name "test" }
        }

        $script:mtMapDir = Join-Path $TestDrive "multi-target"
        New-Item -ItemType Directory -Path $script:mtMapDir -Force | Out-Null
        "@{ 'clean' = { }; 'build' = { }; 'test' = { } }" | Out-File (Join-Path $script:mtMapDir ".build.map.ps1")

        $script:mtCompleter = (Get-Command qbuild).Parameters['entry'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
            Select-Object -First 1
    }

    BeforeEach { $script:mtRan.Clear() }

    It "runs each comma-separated target in order" {
        qbuild -map $script:mtTargets clean, build
        $script:mtRan | Should -Be @("clean", "build")
    }

    It "stops at the first target that throws" {
        $map = @{
            "a" = { Invoke-MTTarget -name "a" }
            "b" = { throw "boom" }
            "c" = { Invoke-MTTarget -name "c" }
        }
        { qbuild -map $map a, b, c } | Should -Throw
        $script:mtRan | Should -Be @("a")
    }

    It "stops at the first target that leaves a non-zero exit code" {
        $map = @{
            "a" = { Invoke-MTTarget -name "a" }
            "b" = { pwsh -NoProfile -Command "exit 3" }
            "c" = { Invoke-MTTarget -name "c" }
        }
        { qbuild -map $map a, b, c } | Should -Throw "*exit code 3*"
        $script:mtRan | Should -Be @("a")
    }

    It "completes entries when configmap.ps1 is dot-sourced instead of imported as a module" {
        $configmapScript = (Resolve-Path "$PSScriptRoot\..\configmap.ps1").Path
        $output = pwsh -NoProfile -Command {
            param($Script, $MapDir)
            . $Script
            Set-Location $MapDir
            $completer = (Get-Command qbuild).Parameters['entry'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
                Select-Object -First 1
            & $completer.ScriptBlock "qbuild" "entry" "" $null @{}
        } -args $configmapScript, $script:mtMapDir

        $output | Should -Contain "clean"
        $output | Should -Contain "build"
        $output | Should -Not -Match "^ERROR"
    }

    It "completes the second target after a comma" {
        Push-Location $script:mtMapDir
        try {
            $completions = & $script:mtCompleter.ScriptBlock "qbuild" "entry" "clean," $null @{}
            $completions | Should -Contain "clean,build"
            $completions | Should -Contain "clean,test"
        } finally { Pop-Location }
    }

    It "filters completions by the partial word after the comma" {
        Push-Location $script:mtMapDir
        try {
            $completions = & $script:mtCompleter.ScriptBlock "qbuild" "entry" "clean,b" $null @{}
            $completions | Should -Contain "clean,build"
            $completions | Should -Not -Contain "clean,test"
        } finally { Pop-Location }
    }

    It "excludes already-selected entries from completions" {
        Push-Location $script:mtMapDir
        try {
            $completions = & $script:mtCompleter.ScriptBlock "qbuild" "entry" "clean," $null @{}
            $completions | Should -Not -Contain "clean,clean"
        } finally { Pop-Location }
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
        $scriptBlock = Get-EntryCommand $entry "exec"

        $parameters = Get-ScriptArgs $ScriptBlock
        $parameters.Keys | Should -Contain "NewVersion"
        $parameters.Keys | Should -Contain "path"
    }

    It "should handle <EntryType> command with -path parameter" -TestCases @(
        @{ EntryType = "push:short" }
        @{ EntryType = "push:exec" }
    ) {
        param($EntryType)
        
        qbuild -map $buildTargets $EntryType -path ".\configmap\"

        Should -Invoke Write-Host -ParameterFilter {
            $Object -eq "Running push/publish workflow with args: NewVersion=False, path=.\configmap\"
        }
    }

    It "should handle <EntryType> command with -NewVersion and -path parameters" -TestCases @(
        @{ EntryType = "push:short" }
        @{ EntryType = "push:exec" }
    ) {
        param($EntryType)
        
        qbuild -map $buildTargets $EntryType -NewVersion -path ".\configmap\"

        Should -Invoke Write-Host -ParameterFilter {
            $Object -eq "Running push/publish workflow with args: NewVersion=True, path=.\configmap\"
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
        Mock Write-Host -ModuleName ConfigMap

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

        Should -Invoke Write-Host -ModuleName ConfigMap -ParameterFilter {
            $Object -match "(?i)subcommand|sub-command|choose|select|specify"
        }
    }

    It "should list the available subcommands" {
        qbuild -map $targets "parent" -ErrorAction SilentlyContinue

        Should -Invoke Write-Host -ModuleName ConfigMap -ParameterFilter {
            "$Object" -match "child-one"
        }
        Should -Invoke Write-Host -ModuleName ConfigMap -ParameterFilter {
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

    It "should generate completion candidates from the canonical entry list" {
        InModuleScope ConfigMap {
            Mock Get-MapEntryList {
                param($map, $flatten)

                if ($flatten) {
                    return [ordered]@{
                        'parent*'    = $map.parent
                        'child'      = $map.parent.child
                        'parent.all' = New-BuildAllEntry
                    }
                }

                return [ordered]@{
                    'parent'       = $map.parent
                    'parent.child' = $map.parent.child
                    'parent.all'   = New-BuildAllEntry
                }
            }
            $map = @{
                parent = @{
                    child = { }
                }
            }

            $completions = @(Get-EntryCompletion -map $map -language build -wordToComplete '')

            $completions | Should -Contain 'parent'
            $completions | Should -Contain 'parent*'
            $completions | Should -Contain 'parent.child'
            $completions | Should -Contain 'child'
            $completions | Should -Contain 'parent.all'
            Should -Invoke Get-MapEntryList -Times 2 -Exactly
        }
    }
}

Describe "qbuild !init" {
    BeforeAll {
        $testRoot = Join-Path $TestDrive "init-test"
        $parentDir = Join-Path $testRoot "parent"
        $childDir = Join-Path $parentDir "child"
        New-Item -ItemType Directory -Path $childDir -Force | Out-Null
    }

    It "should add missing defaults to an existing map and keep what is there" {
        $existingDir = Join-Path $testRoot "existing"
        New-Item -ItemType Directory -Path $existingDir -Force | Out-Null
        "# my comment`n@{ 'test' = { Write-Host 'test' } }" | Out-File (Join-Path $existingDir ".build.map.ps1")

        Push-Location $existingDir
        try {
            qbuild "!init.options"
            $content = Get-Content ".build.map.ps1" -Raw
            $content | Should -Match "# my comment"
            $content | Should -Match "'test' = \{ Write-Host 'test' \}"
            $map = . ".\.build.map.ps1"
            @($map.Keys) | Should -Contain "test"
            @($map.Keys) | Should -Contain "api"
        }
        finally {
            Pop-Location
        }
    }

    It "should only list suboptions and leave the map alone when bare !init finds a map" {
        $listDir = Join-Path $testRoot "list-suboptions"
        New-Item -ItemType Directory -Path $listDir -Force | Out-Null
        $source = "@{ 'test' = { Write-Host 'test' } }"
        $source | Set-Content (Join-Path $listDir ".build.map.ps1") -NoNewline

        Push-Location $listDir
        try {
            $output = qbuild "!init" 6>&1 | Out-String

            $output | Should -Match "already exists"
            foreach ($name in '!init.exec', '!init.options', '!init.steps', '!init.bun', '!init.npm') {
                $output | Should -Match ([regex]::Escape($name))
            }
            Get-Content ".build.map.ps1" -Raw | Should -Be $source
        }
        finally {
            Pop-Location
        }
    }

    It "should pick package managers from <files> on a fresh !init" -TestCases @(
        @{ files = @(); expected = @('build', 'api', 'setup') }
        @{ files = @('package.json'); expected = @('build', 'api', 'setup', 'npm') }
        @{ files = @('bun.lock'); expected = @('build', 'api', 'setup', 'bun') }
        @{ files = @('package.json', 'bun.lock'); expected = @('build', 'api', 'setup', 'bun') }
    ) {
        $detectDir = Join-Path $testRoot "detect-$($files -join '-')"
        New-Item -ItemType Directory -Path $detectDir -Force | Out-Null
        foreach ($name in $files) {
            '{}' | Set-Content (Join-Path $detectDir $name)
        }

        Push-Location $detectDir
        try {
            qbuild "!init"
            $map = . ".\.build.map.ps1"
            @($map.Keys) | Should -Be $expected
        }
        finally {
            Pop-Location
        }
    }

    It "should add !init.<manager> entries without their detection files" -TestCases @(
        @{ manager = 'bun' }
        @{ manager = 'npm' }
    ) {
        $forcedDir = Join-Path $testRoot "forced-$manager"
        New-Item -ItemType Directory -Path $forcedDir -Force | Out-Null

        Push-Location $forcedDir
        try {
            qbuild "!init.$manager"
            $map = . ".\.build.map.ps1"
            @($map.Keys) | Should -Be @($manager)
        }
        finally {
            Pop-Location
        }
    }

    It "should build one map from successive !init.<type> runs on a fresh directory" {
        $freshDir = Join-Path $testRoot "fresh"
        New-Item -ItemType Directory -Path $freshDir -Force | Out-Null

        Push-Location $freshDir
        try {
            qbuild "!init.options"
            qbuild "!init.bun"

            $map = . ".\.build.map.ps1"
            @($map.Keys) | Should -Be @('api', 'bun')
            $map.api._settings.process | Should -Be 'options'
            $map.bun._settings.process | Should -Be 'bun'

            $merged = InModuleScope ConfigMap -Parameters @{ Map = $map } {
                param($Map)
                (Get-ConfigMapSettingsForPath -Map (Merge-ConfigMapCommands -Map $Map -Language build) -Path 'bun').Process
            }
            $merged | Should -Be 'bun'
        }
        finally {
            Pop-Location
        }
    }

    It "should produce a map that lists and runs in an otherwise empty directory" {
        $workingDir = Join-Path $testRoot "working"
        New-Item -ItemType Directory -Path $workingDir -Force | Out-Null

        Push-Location $workingDir
        try {
            qbuild "!init"

            $listing = (qbuild list 6>&1) -join ''
            $listing | Should -Not -Match '-ctx'
            $listing | Should -Match 'Optionslocal, prod|Options local, prod'
            qbuild setup 6>$null
            Get-Content "out/hello.txt" | Should -Be "hello from qbuild"
            qbuild api set local
            Get-Content ".env" | Should -Contain "API_URL=http://localhost:5000"
        }
        finally {
            Pop-Location
        }
    }

    It "should keep blank lines inside a default entry" {
        $blankDir = Join-Path $testRoot "blank-lines"
        New-Item -ItemType Directory -Path $blankDir -Force | Out-Null

        Push-Location $blankDir
        try {
            qbuild "!init.steps"
            (Get-Content ".build.map.ps1" -Raw) | Should -Match '\r?\n\r?\n\s+"write-file"'
        }
        finally {
            Pop-Location
        }
    }

    It "should leave the map byte-identical when every default already exists" {
        $idempotentDir = Join-Path $testRoot "idempotent"
        New-Item -ItemType Directory -Path $idempotentDir -Force | Out-Null

        Push-Location $idempotentDir
        try {
            qbuild "!init.steps"
            $first = [System.IO.File]::ReadAllBytes((Join-Path $idempotentDir ".build.map.ps1"))
            qbuild "!init.steps"
            $second = [System.IO.File]::ReadAllBytes((Join-Path $idempotentDir ".build.map.ps1"))
            $second | Should -Be $first
        }
        finally {
            Pop-Location
        }
    }

    It "should keep a user entry that shares a default's name" {
        $collisionDir = Join-Path $testRoot "collision"
        New-Item -ItemType Directory -Path $collisionDir -Force | Out-Null
        "@{ 'bun' = { 'mine' } }" | Out-File (Join-Path $collisionDir ".build.map.ps1")

        Push-Location $collisionDir
        try {
            qbuild "!init.bun"
            $map = . ".\.build.map.ps1"
            & $map.bun | Should -Be 'mine'
        }
        finally {
            Pop-Location
        }
    }

    It "should insert into <name> maps" -TestCases @(
        @{ name = 'ordered'; source = "[ordered]@{`n    a = { 'a' }`n}`n"; path = @() }
        @{ name = 'variable'; source = "`$targets = @{`n    a = { 'a' }`n}`n`nreturn `$targets`n"; path = @() }
        @{ name = 'list container'; source = "@{`n    list = @{`n        a = { 'a' }`n    }`n}`n"; path = @('list') }
        @{ name = 'empty'; source = "@{}"; path = @() }
    ) {
        $mapFile = Join-Path $testRoot "shape-$name.build.map.ps1"
        $source | Set-Content -LiteralPath $mapFile -NoNewline

        qbuild -map $mapFile "!init.npm"

        $map = . $mapFile
        foreach ($key in $path) { $map = $map[$key] }
        $map.npm._settings.process | Should -Be 'npm'
        if ($name -ne 'empty') {
            & $map.a | Should -Be 'a'
        }
    }

    It "should keep CRLF line endings" {
        $mapFile = Join-Path $testRoot "crlf.build.map.ps1"
        "@{`r`n    a = { 'a' }`r`n}`r`n" | Set-Content -LiteralPath $mapFile -NoNewline

        qbuild -map $mapFile "!init.npm"

        (Get-Content -LiteralPath $mapFile -Raw) | Should -Not -Match "[^\r]\n"
    }

    It "should fail and leave the file alone when the map has no hashtable literal" {
        $mapFile = Join-Path $testRoot "computed.build.map.ps1"
        $source = "New-Object System.Collections.Hashtable"
        $source | Set-Content -LiteralPath $mapFile -NoNewline

        { qbuild -map $mapFile "!init.npm" } | Should -Throw "*Cannot add entries*"

        Get-Content -LiteralPath $mapFile -Raw | Should -Be $source
    }

    It "should offer !init.<type> in completions when a local map exists" {
        $completeDir = Join-Path $testRoot "complete"
        New-Item -ItemType Directory -Path $completeDir -Force | Out-Null
        "@{ 'test' = { Write-Host 'test' } }" | Out-File (Join-Path $completeDir ".build.map.ps1")

        Push-Location $completeDir
        try {
            $completer = (Get-Command qbuild).Parameters['entry'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
                Select-Object -First 1
            $completions = & $completer.ScriptBlock "qbuild" "entry" "!init" $null @{}

            foreach ($name in '!init', '!init.exec', '!init.options', '!init.steps', '!init.bun', '!init.npm') {
                $completions | Should -Contain $name
            }
        }
        finally {
            Pop-Location
        }
    }

    It "should only expose !init.<type> for processes with a template" {
        InModuleScope ConfigMap {
            Register-ConfigMapProcess -Name 'no-template' -Invoke { }
            try {
                @((Get-ConfigMapInternalCommands -Language build)['!init'].list.Keys) | Should -Be @('exec', 'options', 'steps', 'bun', 'npm')
            }
            finally {
                Unregister-ConfigMapProcess -Name 'no-template'
            }
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

    It "should add an npm proxy entry with !init.npm" {
        $npmDir = Join-Path $testRoot "npm-project"
        New-Item -ItemType Directory -Path $npmDir -Force | Out-Null
        Remove-Item (Join-Path $npmDir ".build.map.ps1") -ErrorAction Ignore

        Push-Location $npmDir
        try {
            qbuild "!init.npm"
            $map = . ".\.build.map.ps1"
            @($map.Keys) | Should -Be @('npm')
            $map.npm._settings.process | Should -Be 'npm'
        }
        finally {
            Pop-Location
        }
    }
}

Describe "Format-TmuxCommand" {
    It "builds qbuild with entry and switch parameters" {
        InModuleScope ConfigMap {
            Format-TmuxCommand -mainCommand 'qbuild' -Entry 'build' -BoundParameters @{ NoRestore = $true } -RemainingArguments @() |
                Should -Be 'qbuild build -NoRestore'
        }
    }

    It "includes map path when map is a string" {
        InModuleScope ConfigMap {
            Format-TmuxCommand -mainCommand 'qbuild' -Entry 'build.ui' -BoundParameters @{ map = '.\.build.map.ps1' } -RemainingArguments @() |
                Should -Be "qbuild -map '.\.build.map.ps1' build.ui"
        }
    }

    It "appends passthrough arguments after --" {
        InModuleScope ConfigMap {
            Format-TmuxCommand -mainCommand 'qbuild' -Entry 'build' -BoundParameters @{} -RemainingArguments @('--config=Release') |
                Should -Be 'qbuild build -- --config=Release'
        }
    }
}

Describe "qbuild all" {
    It "adds virtual all entry for parent entries in completion list" {
        InModuleScope ConfigMap {
            $targets = @{
                "build" = @{
                    "ui"  = { Write-Host "ui" }
                    "api" = { Write-Host "api" }
                }
            }

            $completions = Get-CompletionList $targets -language "build" -leafsOnly:$true
            $completions.Keys | Should -Contain "build.all"
            $completions.Keys | Should -Contain "build.ui"
            $completions.Keys | Should -Contain "build.api"
            Test-BuildAllEntry $completions["build.all"] | Should -Be $true
        }
    }

    It "does not add virtual all when parent already defines all" {
        InModuleScope ConfigMap {
            $targets = @{
                "build" = @{
                    "ui"  = { Write-Host "ui" }
                    "all" = { Write-Host "custom all" }
                }
            }

            $completions = Get-CompletionList $targets -language "build" -leafsOnly:$true
            $completions.Keys | Should -Contain "build.all"
            Test-BuildAllEntry $completions["build.all"] | Should -Be $false
        }
    }

    It "does not add virtual all for configuration maps" {
        InModuleScope ConfigMap {
            $targets = @{
                "db" = @{
                    "local"  = @{ get = { "local" } }
                    "remote" = @{ get = { "remote" } }
                }
            }

            $completions = Get-CompletionList $targets -language "conf" -leafsOnly:$true
            $completions.Keys | Should -Not -Contain "db.all"
        }
    }

    It "expands build.all into direct invokable child entries" {
        InModuleScope ConfigMap {
            Mock Write-Host
            $targets = @{
                "build" = @{
                    "ui"  = { Write-Host "ui" }
                    "api" = { Write-Host "api" }
                }
            }

            qbuild -map $targets "build.all"

            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "ui" }
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "api" }
        }
    }

    It "includes hashtable entries with exec scriptblocks" {
        InModuleScope ConfigMap {
            Mock Write-Host
            $targets = @{
                "build" = @{
                    "ui"  = @{
                        exec = { Write-Host "ui" }
                    }
                    "api" = @{
                        exec = { Write-Host "api" }
                    }
                }
            }

            qbuild -map $targets "build.all"

            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "ui" }
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "api" }
        }
    }

    It "does not add virtual all when parent has only nested groups" {
        InModuleScope ConfigMap {
            $targets = @{
                "dev" = @{
                    "servers" = @{
                        "ui"  = { Write-Host "ui" }
                        "api" = { Write-Host "api" }
                    }
                }
            }

            $completions = Get-CompletionList $targets -language "build" -leafsOnly:$true
            $completions.Keys | Should -Not -Contain "dev.all"
        }
    }

    It "does not run nested children when parent has mixed direct and grouped entries" {
        InModuleScope ConfigMap {
            Mock Write-Host
            $targets = @{
                "dev" = @{
                    "ui"      = { Write-Host "ui" }
                    "servers" = @{
                        "api" = { Write-Host "api" }
                    }
                }
            }

            qbuild -map $targets "dev.all"

            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "ui" }
            Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -eq "api" }
        }
    }

    It "skips non-invokable metadata-only children" {
        InModuleScope ConfigMap {
            Mock Write-Host
            $targets = @{
                "build" = @{
                    "ui"   = { Write-Host "ui" }
                    "docs" = @{ description = "readme only" }
                }
            }

            qbuild -map $targets "build.all"

            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "ui" }
        }
    }
}

Describe "qbuild tmux" {
    BeforeEach {
        $script:qbuildTmuxAutoWindowBackup = $env:QCONF_TmuxAutoWindow
        $script:qbuildConcurrentlyBackup = $env:QCONF_Concurrently
        $env:QCONF_TmuxAutoWindow = '1'
        Remove-Item env:QCONF_Concurrently -ErrorAction SilentlyContinue
        InModuleScope ConfigMap {
            Update-ConfigMapSettings | Out-Null
        }
    }

    AfterEach {
        if ($null -eq $script:qbuildTmuxAutoWindowBackup) {
            Remove-Item env:QCONF_TmuxAutoWindow -ErrorAction SilentlyContinue
        }
        else {
            $env:QCONF_TmuxAutoWindow = $script:qbuildTmuxAutoWindowBackup
        }
        if ($null -eq $script:qbuildConcurrentlyBackup) {
            Remove-Item env:QCONF_Concurrently -ErrorAction SilentlyContinue
        }
        else {
            $env:QCONF_Concurrently = $script:qbuildConcurrentlyBackup
        }

        InModuleScope ConfigMap {
            Update-ConfigMapSettings | Out-Null
        }
    }

    It "runs entry locally when not inside tmux" {
        InModuleScope ConfigMap {
            Mock Write-Host
            Mock Invoke-EntryCommand
            Mock Invoke-TmuxCommand
            Mock Get-TmuxInfo { return $null }

            $targets = @{
                "build.ui" = { Write-Host "ran build.ui" }
            }
            qbuild -map $targets "build.ui"

            Should -Invoke Invoke-EntryCommand -Times 1 -Exactly
            Should -Invoke Invoke-TmuxCommand -Times 0 -Exactly
        }
    }

    It "runs entry locally when already in the target window" {
        InModuleScope ConfigMap {
            Mock Write-Host
            Mock Invoke-EntryCommand
            Mock Invoke-TmuxCommand
            Mock Get-TmuxInfo { return [pscustomobject]@{ sessionName = 'dev'; windowName = 'build.ui' } }

            $targets = @{
                "build.ui" = { Write-Host "ran build.ui" }
            }
            qbuild -map $targets "build.ui"

            Should -Invoke Invoke-EntryCommand -Times 1 -Exactly
            Should -Invoke Invoke-TmuxCommand -Times 0 -Exactly
        }
    }

    It "runs entry locally when map is an in-memory hashtable" {
        InModuleScope ConfigMap {
            Mock Write-Host
            Mock Invoke-EntryCommand
            Mock Invoke-TmuxCommand
            Mock Get-TmuxInfo { return [pscustomobject]@{ sessionName = 'dev'; windowName = 'other' } }

            $targets = @{
                "build.ui" = { Write-Host "ran build.ui" }
            }
            qbuild -map $targets "build.ui"

            Should -Invoke Invoke-EntryCommand -Times 1 -Exactly
            Should -Invoke Invoke-TmuxCommand -Times 0 -Exactly
        }
    }

    It "passes absolute working directory when delegating to tmux" {
        $mapFile = Join-Path $TestDrive ".build.map.ps1"
        $workDir = Join-Path $TestDrive "work"
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        @'
@{
    "build.ui" = { Write-Host "ran build.ui" }
}
'@ | Set-Content $mapFile -Encoding utf8
        $expectedDir = (Resolve-Path $workDir).Path

        InModuleScope ConfigMap -ArgumentList $mapFile, $expectedDir {
            param($MapFile, $ExpectedDir)
            Mock Write-Host
            Mock Invoke-EntryCommand
            Mock Invoke-TmuxCommand
            Mock Get-TmuxInfo { return [pscustomobject]@{ sessionName = 'dev'; windowName = 'other' } }

            Push-Location $ExpectedDir
            try {
                qbuild -map $MapFile "build.ui"
            }
            finally {
                Pop-Location
            }

            Should -Invoke Invoke-TmuxCommand -ParameterFilter {
                $WorkingDirectory -eq $ExpectedDir
            }
        }
    }

    It "delegates to tmux window named after entry when in a different window" {
        $mapFile = Join-Path $TestDrive ".build.map.ps1"
        @'
@{
    "build.ui" = { Write-Host "ran build.ui" }
}
'@ | Set-Content $mapFile -Encoding utf8

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
            Mock Write-Host
            Mock Invoke-EntryCommand
            Mock Invoke-TmuxCommand
            Mock Get-TmuxInfo { return [pscustomobject]@{ sessionName = 'dev'; windowName = 'other' } }

            qbuild -map $MapFile "build.ui"

            Should -Invoke Invoke-TmuxCommand -Times 1 -Exactly -ParameterFilter {
                $Session -eq 'dev' -and $Window -eq 'build.ui' -and $Command -match 'qbuild.*build\.ui'
            }
            Should -Invoke Invoke-EntryCommand -Times 0 -Exactly
        }
    }

    It "passes qbuild arguments in the tmux command" {
        $mapFile = Join-Path $TestDrive "map.ps1"
        @'
@{
    "build" = { param([switch]$NoRestore) Write-Host "ran" }
}
'@ | Set-Content $mapFile -Encoding utf8

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
            Mock Write-Host
            Mock Invoke-EntryCommand
            Mock Invoke-TmuxCommand
            Mock Get-TmuxInfo { return [pscustomobject]@{ sessionName = 'dev'; windowName = 'other' } }

            qbuild -map $MapFile "build" -NoRestore

            Should -Invoke Invoke-TmuxCommand -ParameterFilter {
                $Command -match 'qbuild' -and $Command -match 'build' -and $Command -match '-NoRestore'
            }
        }
    }

    It "passes passthrough arguments after -- in the tmux command" {
        $mapFile = Join-Path $TestDrive "map.ps1"
        @'
@{
    "build" = { param([switch]$NoRestore) Write-Host "ran" }
}
'@ | Set-Content $mapFile -Encoding utf8

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
            Mock Write-Host
            Mock Invoke-EntryCommand
            Mock Invoke-TmuxCommand
            Mock Get-TmuxInfo { return [pscustomobject]@{ sessionName = 'dev'; windowName = 'other' } }

            qbuild -map $MapFile "build" -- --config=Release

            Should -Invoke Invoke-TmuxCommand -ParameterFilter {
                $Command -match '-- --config=Release'
            }
        }
    }

    It "delegates each child when running build.all from a different window" {
        $mapFile = Join-Path $TestDrive ".build.map.ps1"
        @'
@{
    "build" = @{
        "ui"  = { Write-Host "ui" }
        "api" = { Write-Host "api" }
    }
}
'@ | Set-Content $mapFile -Encoding utf8

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
            Mock Write-Host
            Mock Invoke-EntryCommand
            Mock Invoke-TmuxCommand
            Mock Get-TmuxInfo { return [pscustomobject]@{ sessionName = 'dev'; windowName = 'shell' } }

            qbuild -map $MapFile "build.all"

            Should -Invoke Invoke-TmuxCommand -Times 2 -Exactly
            Should -Invoke Invoke-TmuxCommand -ParameterFilter { $Window -eq 'build.ui' }
            Should -Invoke Invoke-TmuxCommand -ParameterFilter { $Window -eq 'build.api' }
            Should -Invoke Invoke-EntryCommand -Times 0 -Exactly
        }
    }

    It "prefers tmux over concurrently for build.all when inside tmux" {
        $mapFile = Join-Path $TestDrive ".build.map.ps1"
        @'
@{
    "build" = @{
        "ui"  = { Write-Host "ui" }
        "api" = { Write-Host "api" }
    }
}
'@ | Set-Content $mapFile -Encoding utf8

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
            $script:ConfigMapConcurrentlyInvoker = {
                throw 'concurrently should not run when tmux handles build.all'
            }
            Mock Write-Host
            Mock Invoke-EntryCommand
            Mock Invoke-TmuxCommand
            Mock Get-TmuxInfo { return [pscustomobject]@{ sessionName = 'dev'; windowName = 'shell' } }

            qbuild -map $MapFile "build.all"

            Should -Invoke Invoke-TmuxCommand -Times 2 -Exactly
            Should -Invoke Invoke-EntryCommand -Times 0 -Exactly
        }
    }

    It "runs entry locally when QCONF_TmuxAutoWindow is disabled" {
        $mapFile = Join-Path $TestDrive ".build.map.ps1"
        @'
@{
    "build.ui" = { Write-Host "ran build.ui" }
}
'@ | Set-Content $mapFile -Encoding utf8

        $env:QCONF_TmuxAutoWindow = '0'

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
            Update-ConfigMapSettings | Out-Null
            Mock Write-Host
            Mock Invoke-EntryCommand
            Mock Invoke-TmuxCommand
            Mock Get-TmuxInfo { return [pscustomobject]@{ sessionName = 'dev'; windowName = 'other' } }

            qbuild -map $MapFile "build.ui"

            Should -Invoke Invoke-EntryCommand -Times 1 -Exactly
            Should -Invoke Invoke-TmuxCommand -Times 0 -Exactly
        }
    }
}

Describe "Test-ConfigMapFeatureEnabled TmuxAutoWindow" {
    BeforeEach {
        $script:qbuildTmuxAutoWindowBackup = $env:QCONF_TmuxAutoWindow
        Remove-Item env:QCONF_TmuxAutoWindow -ErrorAction SilentlyContinue
        InModuleScope ConfigMap {
            Update-ConfigMapSettings | Out-Null
        }
    }

    AfterEach {
        if ($null -eq $script:qbuildTmuxAutoWindowBackup) {
            Remove-Item env:QCONF_TmuxAutoWindow -ErrorAction SilentlyContinue
        }
        else {
            $env:QCONF_TmuxAutoWindow = $script:qbuildTmuxAutoWindowBackup
        }

        InModuleScope ConfigMap {
            Update-ConfigMapSettings | Out-Null
        }
    }

    It "is disabled when the env var is unset" {
        InModuleScope ConfigMap {
            Test-ConfigMapFeatureEnabled -Name TmuxAutoWindow | Should -Be $false
        }
    }

    It "is disabled for falsy values" {
        foreach ($value in '0', 'false', 'no', 'off', 'FALSE', 'OFF') {
            $env:QCONF_TmuxAutoWindow = $value
            InModuleScope ConfigMap {
                Update-ConfigMapSettings | Out-Null
                Test-ConfigMapFeatureEnabled -Name TmuxAutoWindow | Should -Be $false
            }
        }
    }

    It "is enabled for truthy values" {
        foreach ($value in '1', 'true', 'yes', 'on') {
            $env:QCONF_TmuxAutoWindow = $value
            InModuleScope ConfigMap {
                Update-ConfigMapSettings | Out-Null
                Test-ConfigMapFeatureEnabled -Name TmuxAutoWindow | Should -Be $true
            }
        }
    }
}