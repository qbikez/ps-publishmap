BeforeDiscovery {
    . "$PSScriptRoot\test-utils.ps1"
}

Describe "Tmux" {
    BeforeAll {
        . "$PSScriptRoot\..\src\plugins\plugin-tmux\tmux.ps1"
    }

    BeforeEach {
        Mock Test-InsideTmux { return $true }
        Mock Invoke-TmuxDisplayMessage
    }

    It "returns an object with sessionName and windowName" {
        Mock Invoke-TmuxDisplayMessage -ParameterFilter { $Format -eq '#{session_name}' } { return 'my-session' }
        Mock Invoke-TmuxDisplayMessage -ParameterFilter { $Format -eq '#{window_name}' } { return 'my-window' }

        $info = Get-TmuxInfo

        $info | Should -MatchObject @{
            sessionName = 'my-session'
            windowName  = 'my-window'
        }
    }

    It "queries tmux for session and window names" {
        Mock Invoke-TmuxDisplayMessage { return 'x' }

        Get-TmuxInfo | Out-Null

        Should -Invoke Invoke-TmuxDisplayMessage -Times 2 -Exactly
        Should -Invoke Invoke-TmuxDisplayMessage -ParameterFilter { $Format -eq '#{session_name}' }
        Should -Invoke Invoke-TmuxDisplayMessage -ParameterFilter { $Format -eq '#{window_name}' }
    }

    It "trims whitespace from tmux output" {
        Mock Invoke-TmuxDisplayMessage -ParameterFilter { $Format -eq '#{session_name}' } { return "  dev  `n" }
        Mock Invoke-TmuxDisplayMessage -ParameterFilter { $Format -eq '#{window_name}' } { return "  shell  " }

        $info = Get-TmuxInfo

        $info.sessionName | Should -Be 'dev'
        $info.windowName | Should -Be 'shell'
    }

    It "returns null when not inside a tmux session" {
        Mock Test-InsideTmux { return $false }

        Get-TmuxInfo | Should -Be $null
    }

    It "does not query tmux when not inside a tmux session" {
        Mock Test-InsideTmux { return $false }

        Get-TmuxInfo | Out-Null

        Should -Invoke Invoke-TmuxDisplayMessage -Times 0 -Exactly
    }
}

Describe "Invoke-TmuxCommand" {
    BeforeAll {
        . "$PSScriptRoot\..\src\plugins\plugin-tmux\tmux.ps1"
    }

    BeforeEach {
        Mock Invoke-TmuxSendKeys
        Mock Test-TmuxSession { return $true }
        Mock Test-TmuxWindow { return $true }
        Mock New-TmuxSession
        Mock New-TmuxWindow
    }

    It "sends the command to the session:window target" {
        Invoke-TmuxCommand -Session 'dev' -Window 'build' -Command 'npm test'

        Should -Invoke Invoke-TmuxSendKeys -Times 1 -Exactly -ParameterFilter {
            $Target -eq 'dev:build' -and $Keys -contains 'npm test'
        }
    }

    It "sends Enter after the command to execute it" {
        Invoke-TmuxCommand -Session 'dev' -Window 'build' -Command 'npm test'

        Should -Invoke Invoke-TmuxSendKeys -ParameterFilter {
            $Keys[-1] -eq 'Enter'
        }
    }

    It "passes the command as a single key argument" {
        Invoke-TmuxCommand -Session 'dev' -Window 'shell' -Command 'git status'

        Should -Invoke Invoke-TmuxSendKeys -ParameterFilter {
            $Keys.Count -eq 2 -and $Keys[0] -eq 'git status' -and $Keys[1] -eq 'Enter'
        }
    }

    It "throws when send-keys fails" {
        Mock Invoke-TmuxSendKeys { throw 'tmux send-keys failed' }

        { Invoke-TmuxCommand -Session 'dev' -Window 'build' -Command 'npm test' } |
            Should -Throw 'tmux send-keys failed'
    }

    It "creates session with window when session does not exist" {
        Mock Test-TmuxSession { return $false }
        Mock Test-TmuxWindow { return $false }

        Invoke-TmuxCommand -Session 'dev' -Window 'build' -Command 'npm test'

        Should -Invoke New-TmuxSession -Times 1 -Exactly -ParameterFilter {
            $SessionName -eq 'dev' -and $WindowName -eq 'build'
        }
        Should -Invoke New-TmuxWindow -Times 0 -Exactly
    }

    It "creates window when session exists but window does not" {
        Mock Test-TmuxSession { return $true }
        Mock Test-TmuxWindow { return $false }

        Invoke-TmuxCommand -Session 'dev' -Window 'build' -Command 'npm test'

        Should -Invoke New-TmuxWindow -Times 1 -Exactly -ParameterFilter {
            $SessionName -eq 'dev' -and $WindowName -eq 'build'
        }
        Should -Invoke New-TmuxSession -Times 0 -Exactly
    }

    It "does not create session or window when both already exist" {
        Invoke-TmuxCommand -Session 'dev' -Window 'build' -Command 'npm test'

        Should -Invoke New-TmuxSession -Times 0 -Exactly
        Should -Invoke New-TmuxWindow -Times 0 -Exactly
    }

    It "changes to working directory before running command" {
        $workDir = Join-Path $TestDrive 'project\src'
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        $expected = [System.IO.Path]::GetFullPath($workDir)

        Invoke-TmuxCommand -Session 'dev' -Window 'build' -Command 'npm test' -WorkingDirectory $workDir

        Should -Invoke Invoke-TmuxSendKeys -Times 1 -Exactly -ParameterFilter {
            $Keys.Count -eq 4 `
                -and $Keys[0] -eq "cd '$expected'" `
                -and $Keys[1] -eq 'Enter' `
                -and $Keys[2] -eq 'npm test' `
                -and $Keys[3] -eq 'Enter'
        }
    }

    It "resolves relative working directory to an absolute path" {
        Push-Location $TestDrive
        try {
            $expected = [System.IO.Path]::GetFullPath('.')
            Invoke-TmuxCommand -Session 'dev' -Window 'build' -Command 'npm test' -WorkingDirectory '.'

            Should -Invoke Invoke-TmuxSendKeys -ParameterFilter {
                $Keys[0] -eq "cd '$expected'"
            }
        }
        finally {
            Pop-Location
        }
    }
}
