BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force
}

Describe 'Initialize-QBuildAgent / qbuild !agent.init' {
    BeforeEach {
        $script:projectRoot = Join-Path $TestDrive "agent-init-$(New-Guid)"
        New-Item -ItemType Directory -Force -Path $script:projectRoot | Out-Null
        $script:userHome = Join-Path $TestDrive "home-$(New-Guid)"
        New-Item -ItemType Directory -Force -Path $script:userHome | Out-Null
    }

    It 'installs the Cursor skill into the project by default' {
        Push-Location $script:projectRoot
        try {
            $result = Initialize-QBuildAgent

            $result.Scope | Should -Be 'project'
            $result.Agent | Should -Be 'cursor'
            $expected = [System.IO.Path]::GetFullPath((Join-Path $script:projectRoot '.cursor/skills/qbuild-discover'))
            $result.Destination | Should -Be $expected
            Test-Path $result.SkillPath | Should -BeTrue
            (Get-Content $result.SkillPath -Raw) | Should -Match 'qbuild discovery'
        }
        finally {
            Pop-Location
        }
    }

    It 'installs into agent-specific project directories' {
        $cases = @(
            @{ Agent = 'cursor'; Relative = '.cursor/skills/qbuild-discover' }
            @{ Agent = 'claude'; Relative = '.claude/skills/qbuild-discover' }
            @{ Agent = 'copilot'; Relative = '.github/skills/qbuild-discover' }
        )

        foreach ($case in $cases) {
            $result = Initialize-QBuildAgent -Scope project -Agent $case.Agent -ProjectRoot $script:projectRoot
            $expected = [System.IO.Path]::GetFullPath((Join-Path $script:projectRoot $case.Relative))
            $result.Destination | Should -Be $expected
            Test-Path $result.SkillPath | Should -BeTrue
        }
    }

    It 'installs into user-scope directories under HOME' {
        $originalHome = $env:HOME
        try {
            $env:HOME = $script:userHome

            $cases = @(
                @{ Agent = 'cursor'; Relative = '.cursor/skills/qbuild-discover' }
                @{ Agent = 'claude'; Relative = '.claude/skills/qbuild-discover' }
                @{ Agent = 'copilot'; Relative = '.copilot/skills/qbuild-discover' }
            )
            foreach ($case in $cases) {
                $result = Initialize-QBuildAgent -Scope user -Agent $case.Agent -ProjectRoot $script:projectRoot
                $expected = [System.IO.Path]::GetFullPath((Join-Path $script:userHome $case.Relative))
                $result.Destination | Should -Be $expected
                Test-Path $result.SkillPath | Should -BeTrue
            }
        }
        finally {
            if ($null -eq $originalHome) {
                Remove-Item Env:HOME -ErrorAction SilentlyContinue
            }
            else {
                $env:HOME = $originalHome
            }
        }
    }

    It 'exposes Scope and Agent dynamic parameters for !agent.init' {
        InModuleScope ConfigMap {
            $params = New-QBuildAgentInitDynamicParam
            @($params.Keys | Sort-Object) | Should -Be @('Agent', 'Scope')

            $scopeSet = $params['Scope'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            @($scopeSet.ValidValues) | Should -Be @('user', 'project')

            $agentSet = $params['Agent'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            @($agentSet.ValidValues) | Should -Be @('cursor', 'copilot', 'claude')
        }
    }

    It 'installs via qbuild !agent.init with defaults' {
        Push-Location $script:projectRoot
        try {
            $result = qbuild '!agent.init'
            $result.Agent | Should -Be 'cursor'
            $result.Scope | Should -Be 'project'
            Test-Path (Join-Path $script:projectRoot '.cursor/skills/qbuild-discover/SKILL.md') | Should -BeTrue
        }
        finally {
            Pop-Location
        }
    }

    It 'installs via qbuild !agent.init -Scope user -Agent claude' {
        $originalHome = $env:HOME
        try {
            $env:HOME = $script:userHome
            Push-Location $script:projectRoot
            try {
                $result = qbuild '!agent.init' -Scope user -Agent claude
                $result.Scope | Should -Be 'user'
                $result.Agent | Should -Be 'claude'
                Test-Path (Join-Path $script:userHome '.claude/skills/qbuild-discover/SKILL.md') | Should -BeTrue
            }
            finally {
                Pop-Location
            }
        }
        finally {
            if ($null -eq $originalHome) {
                Remove-Item Env:HOME -ErrorAction SilentlyContinue
            }
            else {
                $env:HOME = $originalHome
            }
        }
    }

    It 'includes !agent.init in entry completions' {
        Push-Location $script:projectRoot
        try {
            $completer = (Get-Command qbuild).Parameters['entry'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
                Select-Object -First 1

            $completions = & $completer.ScriptBlock 'qbuild' 'entry' '!agent' $null @{}
            $completions | Should -Contain '!agent.init'
        }
        finally {
            Pop-Location
        }
    }
}
