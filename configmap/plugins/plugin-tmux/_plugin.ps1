. "$PSScriptRoot\tmux.ps1"

@{
    name        = 'tmux'
    priority    = 10
    description = 'Tmux support'

    hooks       = @{
        InvokeQBuildTargets = {
            param($Context)

            if (-not (Test-TmuxBatchDispatchEnabled $Context)) {
                Write-Verbose "[tmux] Batch dispatch is not applicable. Skipping tmux handling."
                return @{ Handled = $false }
            }

            Write-Verbose "[tmux] Dispatching $($Context.Targets.Count) target(s) via tmux windows."
            $runContext = $Context.RunContext
            if (-not $runContext) {
                $runContext = New-ConfigMapRunContext -Map $Context.Map
            }
            foreach ($target in $Context.Targets) {
                $targetContext = New-ConfigMapEntryContext -Parent $runContext -EntryKey $target.Key -Entry $target.Value
                Invoke-WithRunContext -Context $targetContext -ScriptBlock {
                    Invoke-EntryWrapper `
                        -MainCommand $Context.MainCommand `
                        -TargetKey $target.Key `
                        -TargetEntry $target.Value `
                        -Command $Context.Command `
                        -Bound $Context.Bound `
                        -RemainingArguments $Context.RemainingArguments `
                        -RunContext $targetContext
                }
            }

            return @{ Handled = $true }
        }

        InvokeEntryWrapper  = {
            param($Context)

            $hasMap = $Context.Bound.map -and $Context.Bound.map -isnot [string]
            if (-not (Test-ConfigMapFeatureEnabled -Name TmuxAutoWindow -Settings $Context.Settings) -or $hasMap) {
                Write-Verbose "[tmux] Auto-window is disabled or map argument is present. Skipping tmux handling."
                return @{ Handled = $false }
            }

            $tmuxInfo = Get-TmuxInfo
            if ($null -eq $tmuxInfo `
                    -or $tmuxInfo.windowName -eq $Context.TargetKey) {
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
