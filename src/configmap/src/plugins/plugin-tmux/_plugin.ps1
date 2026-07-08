@{
    name        = 'tmux'
    description = 'Tmux support'

    hooks       = @{
        InvokeEntryWrapper = {
            param($Context)

            $hasMap = $Context.Bound.map -and $Context.Bound.map -isnot [string]
            if (-not (Test-TmuxAutoWindowEnabled) -or $hasMap) {
                return @{ Handled = $false }
            }

            $tmuxInfo = Get-TmuxInfo
            if ($null -eq $tmuxInfo `
                    -or $tmuxInfo.windowName -eq $Context.TargetKey `
                    -or -not (Test-TmuxAutoWindowEnabled)) {
                return @{ Handled = $false }
            }

            $tmuxCommand = Format-TmuxCommand `
                -mainCommand $Context.MainCommand `
                -Entry $Context.TargetKey `
                -BoundParameters $Context.Bound `
                -RemainingArguments $Context.RemainingArguments

            Invoke-TmuxCommand `
                -Session $tmuxInfo.sessionName `
                -Window $Context.TargetKey `
                -Command $tmuxCommand `
                -WorkingDirectory (Get-Location).Path

            return @{ Handled = $true }
        }
    }
}
