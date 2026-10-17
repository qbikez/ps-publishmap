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

    It 'installs Cursor skills into the project by default' {
        Push-Location $script:projectRoot
        try {
            $result = Initialize-QBuildAgent

            $result.Scope | Should -Be 'project'
            $result.Agent | Should -Be 'cursor'
            $expectedParent = [System.IO.Path]::GetFullPath((Join-Path $script:projectRoot '.cursor/skills'))
            $result.SkillsParent | Should -Be $expectedParent
            $result.Destination | Should -Be $expectedParent
            @($result.Skills).Count | Should -BeGreaterOrEqual 2
            $names = @($result.Skills | ForEach-Object { $_.Name })
            $names | Should -Contain 'qbuild-discover'
            $names | Should -Contain 'qconf-templates'
            foreach ($skill in $result.Skills) {
                Test-Path $skill.SkillPath | Should -BeTrue
            }
            (Get-Content (Join-Path $expectedParent 'qbuild-discover/SKILL.md') -Raw) | Should -Match 'qbuild discovery'
            (Get-Content (Join-Path $expectedParent 'qconf-templates/SKILL.md') -Raw) | Should -Match '_template'
        }
        finally {
            Pop-Location
        }
    }

    It 'installs into agent-specific project directories' {
        $cases = @(
            @{ Agent = 'cursor'; Relative = '.cursor/skills' }
            @{ Agent = 'claude'; Relative = '.claude/skills' }
            @{ Agent = 'copilot'; Relative = '.github/skills' }
        )

        foreach ($case in $cases) {
            $result = Initialize-QBuildAgent -Scope project -Agent $case.Agent -ProjectRoot $script:projectRoot
            $expected = [System.IO.Path]::GetFullPath((Join-Path $script:projectRoot $case.Relative))
            $result.SkillsParent | Should -Be $expected
            Test-Path (Join-Path $expected 'qbuild-discover/SKILL.md') | Should -BeTrue
            Test-Path (Join-Path $expected 'qconf-templates/SKILL.md') | Should -BeTrue
        }
    }

    It 'installs into user-scope directories under HOME' {
        $originalHome = $env:HOME
        try {
            $env:HOME = $script:userHome

            $cases = @(
                @{ Agent = 'cursor'; Relative = '.cursor/skills' }
                @{ Agent = 'claude'; Relative = '.claude/skills' }
                @{ Agent = 'copilot'; Relative = '.copilot/skills' }
            )
            foreach ($case in $cases) {
                $result = Initialize-QBuildAgent -Scope user -Agent $case.Agent -ProjectRoot $script:projectRoot
                $expected = [System.IO.Path]::GetFullPath((Join-Path $script:userHome $case.Relative))
                $result.SkillsParent | Should -Be $expected
                Test-Path (Join-Path $expected 'qbuild-discover/SKILL.md') | Should -BeTrue
                Test-Path (Join-Path $expected 'qconf-templates/SKILL.md') | Should -BeTrue
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
            $map = Merge-ConfigMapCommands -Language build
            $params = Get-EntryDynamicParam -map $map -key '!agent.init' -command exec
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
            Test-Path (Join-Path $script:projectRoot '.cursor/skills/qconf-templates/SKILL.md') | Should -BeTrue
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
                Test-Path (Join-Path $script:userHome '.claude/skills/qconf-templates/SKILL.md') | Should -BeTrue
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
            $completions | Should -Contain '!agent.skills'
        }
        finally {
            Pop-Location
        }
    }
}

Describe 'Show-QBuildAgentSkills / qbuild !agent.skills' {
    It 'prints all shipped skills with headers' {
        $output = qbuild '!agent.skills'
        $text = if ($output -is [array]) { $output -join "`n" } else { [string]$output }

        $text | Should -Match '# skill: qbuild-discover'
        $text | Should -Match '# skill: qconf-templates'
        $text | Should -Match 'qbuild discovery'
        $text | Should -Match '_template'
        $text | Should -Match 'appsettings'
        $text | Should -Match 'dotenv'
    }

    It 'prints a single skill by name' {
        $output = qbuild '!agent.skills' qconf-templates
        $text = if ($output -is [array]) { $output -join "`n" } else { [string]$output }

        $text | Should -Match 'qconf-templates'
        $text | Should -Match '_template'
        $text | Should -Not -Match '# skill: qbuild-discover'
        $text | Should -Not -Match 'qbuild discovery'
    }

    It 'prints a single skill via -Name' {
        $output = qbuild '!agent.skills' -Name qbuild-discover
        $text = if ($output -is [array]) { $output -join "`n" } else { [string]$output }

        $text | Should -Match 'qbuild discovery'
        $text | Should -Not -Match '# skill: qconf-templates'
    }

    It 'throws for an unknown skill name with available names' {
        { qbuild '!agent.skills' nope -ErrorAction Stop } | Should -Throw '*Available*'
        { qbuild '!agent.skills' nope -ErrorAction Stop } | Should -Throw '*qbuild-discover*'
        { qbuild '!agent.skills' nope -ErrorAction Stop } | Should -Throw '*qconf-templates*'
    }

    It 'exposes Name dynamic parameter for !agent.skills' {
        InModuleScope ConfigMap {
            $map = Merge-ConfigMapCommands -Language build
            $params = Get-EntryDynamicParam -map $map -key '!agent.skills' -command exec
            @($params.Keys) | Should -Contain 'Name'
        }
    }
}
