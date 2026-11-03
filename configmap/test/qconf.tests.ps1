BeforeDiscovery {
    . "$PSScriptRoot\test-utils.ps1"
}
BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1
}

Describe "qconf !init" {
    BeforeAll {
        $testRoot = Join-Path $TestDrive "init-test"
        $parentDir = Join-Path $testRoot "parent"
        $childDir = Join-Path $parentDir "child"
        New-Item -ItemType Directory -Path $childDir -Force | Out-Null
    }

    It "should fail when map file already exists in current directory" {
        $existingDir = Join-Path $testRoot "existing"
        New-Item -ItemType Directory -Path $existingDir -Force | Out-Null
        "@{ 'test' = @{ get = { 'value' } } }" | Out-File (Join-Path $existingDir ".configuration.map.ps1")

        Push-Location $existingDir
        try {
            { qconf -entry "!init" } | Should -Throw "*already exists*"
        }
        finally {
            Pop-Location
        }
    }

    It "should create map file even when parent directory has one" {
        # clean up any existing map files first
        Remove-Item (Join-Path $childDir ".configuration.map.ps1") -ErrorAction Ignore

        "@{ 'parent-entry' = @{ get = { 'parent-value' } } }" | Out-File (Join-Path $parentDir ".configuration.map.ps1")

        Push-Location $childDir
        try {
            # !init should create a new file regardless of parent's map
            qconf -entry "!init"
            # verify file was created in child
            Test-Path ".configuration.map.ps1" | Should -BeTrue
        }
        finally {
            Pop-Location
        }
    }

    It "should include !init in completions when no local map but parent has one" {
        # clean up any existing map files first
        Remove-Item (Join-Path $childDir ".configuration.map.ps1") -ErrorAction Ignore

        "@{ 'parent-entry' = @{ get = { 'parent-value' } } }" | Out-File (Join-Path $parentDir ".configuration.map.ps1")

        Push-Location $childDir
        try {
            # simulate tab completion for -entry parameter
            $completer = (Get-Command qconf).Parameters['entry'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
                Select-Object -First 1
            $completions = & $completer.ScriptBlock "qconf" "entry" "" $null @{}

            $completions | Should -Contain "!init"
            $completions | Should -Contain "parent-entry"
        }
        finally {
            Pop-Location
        }
    }
}
