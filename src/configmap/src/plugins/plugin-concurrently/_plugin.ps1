. "$PSScriptRoot\concurrently.ps1"

@{
    name        = 'concurrently'
    description = 'Concurrent execution support'

    hooks       = @{
        InvokeQBuildTargets = {
            param($Context)

            if (-not (Test-ConcurrentlyEnabled)) {
                return @{ Handled = $false }
            }

            $hasMap = $Context.Bound.map -and $Context.Bound.map -isnot [string]
            if ($hasMap) {
                return @{ Handled = $false }
            }

            if (-not (Test-VirtualBuildAllExpansion $Context)) {
                return @{ Handled = $false }
            }

            $boundForCommand = @{}
            foreach ($key in $Context.Bound.Keys) {
                $boundForCommand[$key] = $Context.Bound[$key]
            }
            if (-not ($boundForCommand.map -is [string]) -and $Context.MapPath -is [string]) {
                $boundForCommand.map = $Context.MapPath
            }

            $commands = @()
            $names = @()
            foreach ($target in $Context.Targets) {
                $names += $target.Key
                $commands += Format-QBuildCommand `
                    -mainCommand $Context.MainCommand `
                    -Entry $target.Key `
                    -BoundParameters $boundForCommand `
                    -RemainingArguments $Context.RemainingArguments
            }

            Invoke-ConcurrentlyQBuild -Commands $commands -Names $names
            return @{ Handled = $true }
        }
    }
}
