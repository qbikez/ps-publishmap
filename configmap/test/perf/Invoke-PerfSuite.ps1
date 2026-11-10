#requires -version 7.0
<#
.SYNOPSIS
    Runs the qbuild performance scenarios against one configmap module and emits JSON.
.DESCRIPTION
    Run in a fresh pwsh process. Public scenarios only use qbuild, `qbuild list` and
    TabExpansion2, so the same suite can measure an older module checkout (A/B in
    Compare-Perf.ps1). Internal scenarios call exported helpers and are skipped when
    the module does not have them.

    Cache states:
      warm      - repeated call in a loaded session (discovery cache memory hit)
      edited    - a child map was just touched, so the discovery cache is rebuilt
      new-shell - fresh pwsh: first TAB on the fixture (discovery cache disk hit),
                  excluding module import and one-time session warm-up

    Module load time ('module' fixture) is Import-Module in a fresh pwsh, measured
    once per run independent of the fixtures, with its allocations.

    -ProfileDir traces one extra run of every in-process scenario with the Profiler
    module (Install-PSResource Profiler) after it is timed, so timings are unaffected.
    It writes <fixture>-<scenario>.speedscope.json (open in https://speedscope.app)
    and profile-report.md with the slowest functions and lines by self time.
    new-shell and module import scenarios run in child processes and are not traced.
.EXAMPLE
    ./Invoke-PerfSuite.ps1
.EXAMPLE
    ./Invoke-PerfSuite.ps1 -Fixture samples -ProfileDir ./perf-profile
.EXAMPLE
    ./Invoke-PerfSuite.ps1 -FixtureRoot $env:TEMP/perf -OutFile result.json
#>
[CmdletBinding()]
param(
    [string]$ModulePath = (Join-Path $PSScriptRoot '..\..\configmap.psm1'),
    # Prepared by New-PerfFixture.ps1. Omitted: a temporary copy of all fixtures.
    [string]$FixtureRoot,
    # flat-1k also runs the in-memory internal helper scenarios.
    [ValidateSet('workspace-M', 'workspace-XL', 'flat-1k', 'samples')]
    [string[]]$Fixture = @('workspace-M', 'workspace-XL', 'flat-1k', 'samples'),
    [ValidateRange(3, 10000)]
    [int]$Iterations = 10,
    # Slow scenarios stop after this many seconds (but run at least 3 iterations).
    [double]$ScenarioBudgetSeconds = 8,
    [ValidateRange(1, 1000)]
    [int]$NewShellIterations = 8,
    [ValidateRange(1, 1000)]
    [int]$ImportIterations = 10,
    [string]$Label = 'local',
    [string]$OutFile,
    # Traces each in-process scenario with the Profiler module and writes the results here.
    [string]$ProfileDir,
    # Functions and lines listed per scenario in profile-report.md.
    [ValidateRange(1, 50)]
    [int]$ProfileTop = 10
)

$ErrorActionPreference = 'Stop'

# Ambient QCONF_* settings (cache location, opt-outs) would skew results.
Get-ChildItem env: | Where-Object Name -like 'QCONF_*' | ForEach-Object { Remove-Item "env:$($_.Name)" }

$ModulePath = (Resolve-Path $ModulePath).Path
$tempFixtures = $null
if (!$FixtureRoot) {
    $tempFixtures = Join-Path ([System.IO.Path]::GetTempPath()) "configmap-perf-fixtures-$([guid]::NewGuid())"
    & (Join-Path $PSScriptRoot 'New-PerfFixture.ps1') -Path $tempFixtures -Name $Fixture
    $FixtureRoot = $tempFixtures
}
$FixtureRoot = (Resolve-Path $FixtureRoot).Path
Import-Module $ModulePath -Force
$profileReport = $null
if ($ProfileDir) {
    Import-Module Profiler -ErrorAction Stop
    $ProfileDir = (New-Item -ItemType Directory -Path $ProfileDir -Force).FullName
    $profileReport = [System.Text.StringBuilder]::new()
}

. (Join-Path $PSScriptRoot 'perf-measure.ps1')

$results = [System.Collections.Generic.List[object]]::new()
$startLocation = Get-Location

try {
    $results.Add((Measure-ModuleImport))

    foreach ($fixture in @('workspace-M', 'workspace-XL') | Where-Object { $_ -in $Fixture }) {
        $dir = Join-Path $FixtureRoot $fixture
        if (!(Test-Path $dir)) { continue }
        Set-Location $dir
        $childMap = Join-Path $dir 'p03\.build.map.ps1'
        $touch = { (Get-Item -LiteralPath $childMap -Force).LastWriteTimeUtc = [datetime]::UtcNow }.GetNewClosure()

        $list = { qbuild list 6>&1 | Out-String }
        $results.Add((Measure-Scenario -Name 'list (warm)' -Fixture $fixture -Action $list))
        $results.Add((Measure-Scenario -Name 'list (edited)' -Fixture $fixture -Action $list -Setup $touch))

        $tabs = [ordered]@{
            'TAB entry'       = 'qbuild '
            'TAB nested'      = 'qbuild p03.tools.db.'
            'TAB param name'  = 'qbuild p03.build -'
            'TAB param value' = 'qbuild p03.build -Configuration '
            'TAB pkg script'  = 'qbuild p03.web '
        }
        foreach ($kv in $tabs.GetEnumerator()) {
            $results.Add((Measure-Scenario -Name "$($kv.Key) (warm)" -Fixture $fixture -Action { param($l) Measure-Tab $l } -ArgumentList $kv.Value))
        }
        $entryTab = { Measure-Tab 'qbuild ' }
        $results.Add((Measure-Scenario -Name 'TAB entry (edited)' -Fixture $fixture -Action $entryTab -Setup $touch))

        foreach ($r in Measure-NewShell -Fixture $fixture -Directory $dir -Line 'qbuild ') { $results.Add($r) }
    }

    $samplesDir = Join-Path $FixtureRoot 'samples'
    if ('samples' -in $Fixture -and (Test-Path $samplesDir)) {
        Set-Location $samplesDir
        $rootMap = Join-Path $samplesDir '.build.map.ps1'
        $touchRoot = { (Get-Item -LiteralPath $rootMap -Force).LastWriteTimeUtc = [datetime]::UtcNow }.GetNewClosure()
        $results.Add((Measure-Scenario -Name 'list (warm)' -Fixture 'samples' -Action { qbuild list 6>&1 | Out-String }))
        $results.Add((Measure-Scenario -Name 'TAB entry (warm)' -Fixture 'samples' -Action { Measure-Tab 'qbuild ' }))
        $results.Add((Measure-Scenario -Name 'TAB entry (edited)' -Fixture 'samples' -Action { Measure-Tab 'qbuild ' } -Setup $touchRoot))
        foreach ($r in Measure-NewShell -Fixture 'samples' -Directory $samplesDir -Line 'qbuild ') { $results.Add($r) }
    }

    $flatDir = Join-Path $FixtureRoot 'flat-1k'
    if ('flat-1k' -in $Fixture -and (Test-Path $flatDir)) {
        Set-Location $flatDir
        $results.Add((Measure-Scenario -Name 'list (warm)' -Fixture 'flat-1k' -Action { qbuild list 6>&1 | Out-String }))
        $results.Add((Measure-Scenario -Name 'TAB entry (warm)' -Fixture 'flat-1k' -Action { Measure-Tab 'qbuild ' }))
    }

    # Internal helpers: report-only, they may legitimately change shape between versions.
    if ('flat-1k' -in $Fixture -and (Get-Command Get-MapEntries, Get-EntryCompletion -Module ConfigMap -ErrorAction Ignore).Count -eq 2) {
        $map = [ordered]@{}
        foreach ($n in 1..1000) { $map["task$n"] = { } }
        $results.Add((Measure-Scenario -Name 'internal: Get-MapEntries' -Fixture 'in-memory-1k' -Gate $false -Action {
                    @(Get-MapEntries $map 'task500' -language build)
                }))
        $results.Add((Measure-Scenario -Name 'internal: Get-EntryCompletion' -Fixture 'in-memory-1k' -Gate $false -Action {
                    @(Get-EntryCompletion -map $map -language build -wordToComplete '')
                }))
    }
    $xlMap = Join-Path $FixtureRoot 'workspace-XL\.build.map.ps1'
    if ('workspace-XL' -in $Fixture -and (Test-Path $xlMap)) {
        $results.Add((Measure-Scenario -Name 'internal: Import-ConfigMap' -Fixture 'workspace-XL' -Gate $false -Action {
                    Import-ConfigMap -Map $xlMap -LookUp:$false
                }))
    }
}
finally {
    Set-Location $startLocation
    if ($tempFixtures) { Remove-Item $tempFixtures -Recurse -Force -ErrorAction Ignore }
}

$report = [ordered]@{
    label      = $Label
    module     = $ModulePath
    pwsh       = $PSVersionTable.PSVersion.ToString()
    os         = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    iterations = $Iterations
    results    = $results
}

if ($profileReport) {
    $header = "# qbuild profile`n`n$ModulePath, pwsh $($PSVersionTable.PSVersion). One traced run per scenario after timing; sorted by self time.`n`n"
    $profilePath = Join-Path $ProfileDir 'profile-report.md'
    ($header + $profileReport.ToString()) | Set-Content $profilePath
    Write-Host "profile: $profilePath" -ForegroundColor DarkGray
}

if ($OutFile) {
    $report | ConvertTo-Json -Depth 5 | Set-Content $OutFile
}
else {
    $results | Format-Table -AutoSize | Out-String | Write-Host
}
