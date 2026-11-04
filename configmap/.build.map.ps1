$targets = @{
    "test"      = {
        invoke-pester .
    }
    "test.perf" = @{
        description = "A/B performance comparison against a base revision (test/perf/Compare-Perf.ps1)"
        exec        = {
            param(
                $_context,
                [ValidateSet('@fixtures')]
                [string[]]$Fixture
            )
            $perfArgs = @{}
            if ($Fixture) { $perfArgs.Fixture = $Fixture }
            & (Join-Path $_context.mapDir "test/perf/Compare-Perf.ps1") @perfArgs
        }
        # Fixture names come from Compare-Perf's own ValidateSet
        fixtures    = {
            (Get-Command "$PSScriptRoot/test/perf/Compare-Perf.ps1").Parameters.Fixture.Attributes.ValidValues
        }
    }
}

return $targets
