. "$PSScriptRoot\tmux.ps1"

@{
    name        = 'tmux'
    description = 'Tmux support'

    hooks       = @{
        InvokeEntryWrapper = {
            param($Context)

            $hasMap = $Context.Bound.map -and $Context.Bound.map -isnot [string]
            if (-not (Test-TmuxAutoWindowEnabled) -or $hasMap) {
                Write-Verbose "[tmux] Auto-window is disabled or map argument is present. Skipping tmux handling."
                return @{ Handled = $false }
            }

            $tmuxInfo = Get-TmuxInfo
            if ($null -eq $tmuxInfo `
                    -or $tmuxInfo.windowName -eq $Context.TargetKey `
                    -or -not (Test-TmuxAutoWindowEnabled)) {
                Write-Verbose "[tmux] Auto-window is disabled or already in the target window. Skipping tmux handling."
                return @{ Handled = $false }
            }

            $tmuxCommand = Format-TmuxCommand `
                -mainCommand $Context.MainCommand `
                -Entry $Context.TargetKey `
                -BoundParameters $Context.Bound `
                -RemainingArguments $Context.RemainingArguments

            Write-Verbose "[tmux] Invoking command in tmux session '$($tmuxInfo.sessionName)', window '$($Context.TargetKey)': $tmuxCommand"
            Invoke-TmuxCommand `
                -Session $tmuxInfo.sessionName `
                -Window $Context.TargetKey `
                -Command $tmuxCommand `
                -WorkingDirectory (Get-Location).Path

            return @{ Handled = $true }
        }
    }
}
