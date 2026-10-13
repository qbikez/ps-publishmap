BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force
}

Describe 'Get-ConfigMapCommandCatalog' {
    BeforeAll {
        $script:map = [ordered]@{
            clean = { 'clean' }
            build = @{
                exec        = {
                    param(
                        [string]$Configuration = 'Debug',
                        [ValidateSet('Debug', 'Release')][string]$Mode = 'Debug',
                        [switch]$NoRestore
                    )
                    $Configuration
                }
                description = 'Build the project'
            }
            parent = @{
                description = 'Parent group'
                child       = {
                    param([string]$x = 'a')
                    $x
                }
            }
        }
    }

    It 'returns the same command names as Get-CompletionList' {
        $catalogNames = @(Get-ConfigMapCommandCatalog -Map $script:map -Language build).Name
        $completionNames = @((Get-CompletionList -map $script:map -language build).Keys)
        $catalogNames | Should -Be $completionNames
    }

    It 'includes description, ValidateSet, switches, and defaults' {
        $build = Get-ConfigMapCommandCatalog -Map $script:map -Path build -Language build
        $build.Description | Should -Be 'Build the project'
        $build.IsParent | Should -BeFalse

        $build.Parameters.Name | Should -Be @('Configuration', 'Mode', 'NoRestore')

        $configuration = $build.Parameters | Where-Object Name -EQ Configuration
        $configuration.Type | Should -Be 'string'
        $configuration.IsSwitch | Should -BeFalse
        $configuration.DefaultValue | Should -Be 'Debug'
        $configuration.ValidateSet | Should -Be @()

        $mode = $build.Parameters | Where-Object Name -EQ Mode
        $mode.ValidateSet | Should -Be @('Debug', 'Release')
        $mode.DefaultValue | Should -Be 'Debug'

        $noRestore = $build.Parameters | Where-Object Name -EQ NoRestore
        $noRestore.IsSwitch | Should -BeTrue
        $noRestore.Type | Should -Be 'switch'
    }

    It 'marks parent entries and includes nested children' {
        $parent = Get-ConfigMapCommandCatalog -Map $script:map -Path parent -Language build
        $parent.IsParent | Should -BeTrue
        $parent.Description | Should -Be 'Parent group'
        $parent.Parameters | Should -BeNullOrEmpty

        $child = Get-ConfigMapCommandCatalog -Map $script:map -Path 'parent.child' -Language build
        $child.IsParent | Should -BeFalse
        $child.Parameters[0].Name | Should -Be 'x'
        $child.Parameters[0].DefaultValue | Should -Be 'a'
    }

    It 'filters to a single entry by Path' {
        $result = @(Get-ConfigMapCommandCatalog -Map $script:map -Path build -Language build)
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'build'
    }

    It 'throws for an unknown Path' {
        { Get-ConfigMapCommandCatalog -Map $script:map -Path 'does-not-exist' -Language build } |
            Should -Throw -ExpectedMessage "*does-not-exist*"
    }

    It 'returns empty Parameters for scriptblock entries without param()' {
        $clean = Get-ConfigMapCommandCatalog -Map $script:map -Path clean -Language build
        $clean.Description | Should -Be ''
        $clean.Parameters | Should -BeNullOrEmpty
    }
}

Describe 'qbuild !describe' {
    BeforeAll {
        $script:tempRoot = Join-Path $TestDrive 'qbuild-describe'
        New-Item -ItemType Directory -Force -Path $script:tempRoot | Out-Null
        @'
@{
    build = @{
        exec = {
            param([string]$Configuration = "Debug")
            $Configuration
        }
        description = "Build"
    }
    clean = {
        "clean"
    }
}
'@ | Set-Content -Path (Join-Path $script:tempRoot '.build.map.ps1')
    }

    It 'returns catalog objects for the local map' {
        Push-Location $script:tempRoot
        try {
            $result = @(qbuild '!describe')
            $result.Count | Should -BeGreaterThan 0
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'Parameters'
            $result.Name | Should -Contain 'build'
            $result.Name | Should -Contain 'clean'

            $build = $result | Where-Object Name -EQ build
            $build.Description | Should -Be 'Build'
            $build.Parameters[0].DefaultValue | Should -Be 'Debug'
        }
        finally {
            Pop-Location
        }
    }

    It 'filters by command path' {
        Push-Location $script:tempRoot
        try {
            $result = @(qbuild '!describe' 'build')
            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'build'
        }
        finally {
            Pop-Location
        }
    }

    It 'throws when map is missing' {
        $emptyDir = Join-Path $TestDrive 'no-map'
        New-Item -ItemType Directory -Force -Path $emptyDir | Out-Null
        Push-Location $emptyDir
        try {
            { qbuild '!describe' } | Should -Throw -ExpectedMessage "*No build map file found*"
        }
        finally {
            Pop-Location
        }
    }

    It 'throws for unknown command path' {
        Push-Location $script:tempRoot
        try {
            { qbuild '!describe' 'missing' } | Should -Throw -ExpectedMessage "*missing*"
        }
        finally {
            Pop-Location
        }
    }

    It 'includes built-in list and help in entry completions when a map exists' {
        Push-Location $script:tempRoot
        try {
            $completer = (Get-Command qbuild).Parameters['entry'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
                Select-Object -First 1

            $completions = & $completer.ScriptBlock 'qbuild' 'entry' '' $null @{}

            $completions | Should -Contain 'list'
            $completions | Should -Contain 'help'
            $completions | Should -Contain '!describe'
            $completions | Should -Contain '!settings'
            $completions | Should -Contain '!agent.init'
            $completions | Should -Contain '!cache'
            $completions | Should -Contain 'build'
        }
        finally {
            Pop-Location
        }
    }
}
