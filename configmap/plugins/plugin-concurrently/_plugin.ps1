. "$PSScriptRoot\concurrently.ps1"

@{
    name        = 'concurrently'
    priority    = 50
    description = 'Concurrent execution support'

    hooks       = @{
        InvokeQBuildTargets = {
            param($Context)

            if (-not (Test-ConcurrentlyEnabled -Settings $Context.Settings)) {
                return @{ Handled = $false }
            }

            $hasMap = $Context.Bound.map -and $Context.Bound.map -isnot [string]
            if ($hasMap) {
                return @{ Handled = $false }
            }

            if (-not (Test-VirtualBuildAllExpansion $Context)) {
                return @{ Handled = $false }
            }

            if (-not (Test-ConcurrentlyAvailable)) {
                return @{ Handled = $false }
            }

            $boundForCommand = @{}
            foreach ($key in $Context.Bound.Keys) {
                $boundForCommand[$key] = $Context.Bound[$key]
            }
            if (-not ($boundForCommand.map -is [string]) -and $Context.MapPath -is [string]) {
                $boundForCommand.map = $Context.MapPath
            }

            $commands = [ordered]@{}
            foreach ($target in $Context.Targets) {
                $targetBound = $boundForCommand
                # The parent already ran this target's dependencies; the child process must not repeat them.
                if (Test-ConfigMapEntryHasDependency $target.Value) {
                    $targetBound = $boundForCommand.Clone()
                    $targetBound.NoDeps = $true
                }
                $commands[$target.Key] = Format-QBuildCommand `
                    -mainCommand $Context.MainCommand `
                    -Entry $target.Key `
                    -BoundParameters $targetBound `
                    -RemainingArguments $Context.RemainingArguments
            }

            Invoke-Concurrently -Commands $commands
            return @{ Handled = $true }
        }
    }
}
