BeforeDiscovery {
    $script:hasProfiler = [bool](Get-Module -ListAvailable Profiler)
}

Describe 'Invoke-PerfSuite.ps1' {
    BeforeAll {
        $script:suite = Join-Path $PSScriptRoot 'perf/Invoke-PerfSuite.ps1'

        # A fresh pwsh keeps the suite's Import-Module -Force and env changes out of this session.
        function Invoke-Suite {
            param([string[]]$Arguments)
            $out = Join-Path $TestDrive "result-$(New-Guid).json"
            $argList = @('-NoProfile', '-NonInteractive', '-File', $script:suite,
                '-Iterations', '3', '-ScenarioBudgetSeconds', '0', '-NewShellIterations', '1', '-ImportIterations', '1',
                '-OutFile', $out) + $Arguments
            $log = pwsh @argList *>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw "Invoke-PerfSuite.ps1 failed:`n$log" }
            Get-Content $out -Raw | ConvertFrom-Json
        }
    }

    It '-Fixture runs only the selected fixture (plus the module import row)' {
        $report = Invoke-Suite @('-Fixture', 'samples')

        $fixtures = @($report.results.Fixture | Sort-Object -Unique)
        $fixtures | Should -Be @('module', 'samples')
        @($report.results | Where-Object Error) | Should -BeNullOrEmpty
    }

    It '-ProfileDir writes a speedscope trace per in-process scenario and a report' -Skip:(!$hasProfiler) {
        $profileDir = Join-Path $TestDrive 'profile'

        $report = Invoke-Suite @('-Fixture', 'samples', '-ProfileDir', $profileDir)

        $inProcess = @($report.results | Where-Object { $_.Fixture -eq 'samples' -and $_.Scenario -notlike 'new-shell*' })
        $inProcess.Count | Should -BeGreaterThan 0
        @(Get-ChildItem $profileDir -Filter '*.speedscope.json').Count | Should -Be $inProcess.Count
        $md = Get-Content (Join-Path $profileDir 'profile-report.md') -Raw
        foreach ($r in $inProcess) { $md | Should -Match ([regex]::Escape($r.Scenario)) }
        $md | Should -Match 'Self ms'
    }
}
