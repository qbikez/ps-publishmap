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

function Measure-Scenario {
    param(
        [string]$Name,
        [string]$Fixture,
        [scriptblock]$Action,
        [scriptblock]$Setup,
        [object[]]$ArgumentList = @(),
        [bool]$Gate = $true
    )

    $times = [System.Collections.Generic.List[double]]::new()
    $allocs = [System.Collections.Generic.List[long]]::new()
    try {
        if ($Setup) { & $Setup }
        $null = & $Action @ArgumentList

        $budget = [System.Diagnostics.Stopwatch]::StartNew()
        while ($times.Count -lt $Iterations -and ($times.Count -lt 3 -or $budget.Elapsed.TotalSeconds -lt $ScenarioBudgetSeconds)) {
            if ($Setup) { & $Setup }
            $before = [GC]::GetTotalAllocatedBytes($true)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $null = & $Action @ArgumentList
            $sw.Stop()
            $allocs.Add([GC]::GetTotalAllocatedBytes($true) - $before)
            $times.Add($sw.Elapsed.TotalMilliseconds)
        }
    }
    catch {
        # e.g. a base checkout that does not support a feature used by the fixture
        Write-Host ("  {0,-14} {1,-34} FAILED: {2}" -f $Fixture, $Name, $_) -ForegroundColor Yellow
        return [pscustomobject]@{ Scenario = $Name; Fixture = $Fixture; Gate = $Gate; Error = "$_" }
    }

    $result = New-ScenarioResult -Name $Name -Fixture $Fixture -Gate $Gate -Times $times -Allocs $allocs
    Write-Host ("  {0,-14} {1,-34} median {2,9:n1} ms  (n={3})" -f $Fixture, $Name, $result.MedianMs, $result.Iterations) -ForegroundColor DarkGray
    if ($ProfileDir) { Trace-Scenario -Name $Name -Fixture $Fixture -Action $Action -Setup $Setup -ArgumentList $ArgumentList }
    $result
}

function Trace-Scenario {
    param([string]$Name, [string]$Fixture, [scriptblock]$Action, [scriptblock]$Setup, [object[]]$ArgumentList)

    $slug = "$Fixture-$Name" -replace '[^\w.-]+', '-' -replace '-+$', ''
    $exportPath = Join-Path $ProfileDir $slug
    if ($Setup) { & $Setup }
    # Trace-Script runs the block from the Profiler module, so bind our variables now.
    $traced = { $null = & $Action @ArgumentList }.GetNewClosure()
    $trace = Trace-Script -ScriptBlock $traced -DisableWarning -ExportPath $exportPath 6>$null
    Write-Host ("  {0,-14} {1,-34} traced  {2,9:n1} ms  -> {3}.speedscope.json" -f $Fixture, $Name, $trace.TotalDuration.TotalMilliseconds, $slug) -ForegroundColor DarkGray
    Add-ProfileSection -Name $Name -Fixture $Fixture -Trace $trace -File "$slug.speedscope.json"
}

function Add-ProfileSection {
    param([string]$Name, [string]$Fixture, $Trace, [string]$File)

    $ms = { param($t) [string]::Format([cultureinfo]::InvariantCulture, '{0:0.0}', $t.TotalMilliseconds) }
    $cell = { param($s) "$s" -replace '\|', '\|' -replace '\s+', ' ' }
    $md = $profileReport
    [void]$md.AppendLine("## $Fixture / $Name")
    [void]$md.AppendLine()
    [void]$md.AppendLine("Traced run: $(& $ms $Trace.TotalDuration) ms (tracing overhead included). Flame graph: ``$File``")
    [void]$md.AppendLine()
    [void]$md.AppendLine('| Function | Module | Self ms | Self % | Total ms | Calls |')
    [void]$md.AppendLine('|---|---|--:|--:|--:|--:|')
    foreach ($f in $Trace.Top50FunctionSelfDuration | Select-Object -First $ProfileTop) {
        [void]$md.AppendLine("| $(& $cell $f.Function) | $($f.Module) | $(& $ms $f.SelfDuration) | $($f.SelfPercent) | $(& $ms $f.Duration) | $($f.HitCount) |")
    }
    [void]$md.AppendLine()
    [void]$md.AppendLine('| Line | Function | Self ms | Self % | Hits | Text |')
    [void]$md.AppendLine('|---|---|--:|--:|--:|---|')
    foreach ($l in $Trace.Top50SelfDuration | Select-Object -First $ProfileTop) {
        $text = & $cell $l.Text
        if ($text.Length -gt 80) { $text = $text.Substring(0, 77) + '...' }
        [void]$md.AppendLine("| $($l.File):$($l.Line) | $(& $cell $l.Function) | $(& $ms $l.SelfDuration) | $($l.SelfPercent) | $($l.HitCount) | ``$text`` |")
    }
    [void]$md.AppendLine()
}

function New-ScenarioResult {
    param([string]$Name, [string]$Fixture, [bool]$Gate, $Times, $Allocs)

    $t = @($Times | Sort-Object)
    $a = @($Allocs | Sort-Object)
    $p95 = [math]::Ceiling($t.Count * 0.95) - 1
    [pscustomobject]@{
        Scenario      = $Name
        Fixture       = $Fixture
        Gate          = $Gate
        Iterations    = $t.Count
        MedianMs      = [math]::Round($t[[int]($t.Count / 2)], 3)
        P95Ms         = [math]::Round($t[$p95], 3)
        MinMs         = [math]::Round($t[0], 3)
        MedianAllocKB = if ($a.Count) { [math]::Round($a[[int]($a.Count / 2)] / 1KB, 1) } else { $null }
        Error         = $null
    }
}

function Measure-Tab {
    param([string]$Line, [int]$Min = 1)

    $found = (TabExpansion2 $Line $Line.Length).CompletionMatches
    if ($found.Count -lt $Min) {
        throw "TabExpansion2 '$Line' returned $($found.Count) matches, expected at least $Min."
    }
}

function Invoke-FreshShell {
    param([scriptblock]$Probe, [object[]]$ArgumentList)

    $quoted = $ArgumentList | ForEach-Object { "'$($_ -replace "'", "''")'" }
    $command = "& { $Probe } $quoted"
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
    pwsh -NoProfile -NonInteractive -EncodedCommand $encoded | Select-Object -Last 1 | ConvertFrom-Json
}

function Measure-ModuleImport {
    $probe = {
        param($ModulePath)
        Get-ChildItem env: | Where-Object Name -like 'QCONF_*' | ForEach-Object { Remove-Item "env:$($_.Name)" }
        $before = [GC]::GetTotalAllocatedBytes($true)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Import-Module $ModulePath
        $ms = $sw.Elapsed.TotalMilliseconds
        $alloc = [GC]::GetTotalAllocatedBytes($true) - $before
        $loaded = [bool](Get-Command qbuild -ErrorAction Ignore)
        @{ ms = $ms; alloc = $alloc; loaded = $loaded } | ConvertTo-Json -Compress
    }

    $name = 'Import-Module (new shell)'
    $times = [System.Collections.Generic.List[double]]::new()
    $allocs = [System.Collections.Generic.List[long]]::new()
    try {
        # Untimed: the first load of the module files can be slowed by disk/AV caches.
        $null = Invoke-FreshShell -Probe $probe -ArgumentList $ModulePath
        foreach ($i in 1..$ImportIterations) {
            $r = Invoke-FreshShell -Probe $probe -ArgumentList $ModulePath
            if (!$r.loaded) { throw 'Import-Module did not export qbuild.' }
            $times.Add($r.ms)
            $allocs.Add($r.alloc)
        }
    }
    catch {
        Write-Host ("  {0,-14} {1,-34} FAILED: {2}" -f 'module', $name, $_) -ForegroundColor Yellow
        return [pscustomobject]@{ Scenario = $name; Fixture = 'module'; Gate = $true; Error = "$_" }
    }

    $result = New-ScenarioResult -Name $name -Fixture 'module' -Gate $true -Times $times -Allocs $allocs
    Write-Host ("  {0,-14} {1,-34} median {2,9:n1} ms  (n={3})" -f 'module', $name, $result.MedianMs, $result.Iterations) -ForegroundColor DarkGray
    $result
}

function Measure-NewShell {
    param([string]$Fixture, [string]$Directory, [string]$Line)

    $probe = {
        param($ModulePath, $Directory, $WarmupDirectory, $Line)
        Get-ChildItem env: | Where-Object Name -like 'QCONF_*' | ForEach-Object { Remove-Item "env:$($_.Name)" }
        Import-Module $ModulePath
        # Untimed TAB on an identical copy: pays the one-time code costs of a new
        # session (script compilation, type loading) through the same code paths,
        # so the timed TAB measures only the disk cache load and the map work.
        Set-Location $WarmupDirectory
        $null = TabExpansion2 $Line $Line.Length
        Set-Location $Directory
        $before = [GC]::GetTotalAllocatedBytes($true)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $count = (TabExpansion2 $Line $Line.Length).CompletionMatches.Count
        $tabMs = $sw.Elapsed.TotalMilliseconds
        $alloc = [GC]::GetTotalAllocatedBytes($true) - $before
        @{ tabMs = $tabMs; alloc = $alloc; count = $count } | ConvertTo-Json -Compress
    }
    # A sibling keeps relative paths and parent-map lookups identical.
    $warmup = "$Directory-warmup"
    $probeArgs = @($ModulePath, $Directory, $warmup, $Line)

    $tab = [System.Collections.Generic.List[double]]::new()
    $allocs = [System.Collections.Generic.List[long]]::new()
    try {
        Copy-Item $Directory $warmup -Recurse -Force
        # Writes the disk cache of both copies so every timed run is a disk hit.
        $null = Invoke-FreshShell -Probe $probe -ArgumentList $probeArgs

        foreach ($i in 1..$NewShellIterations) {
            $r = Invoke-FreshShell -Probe $probe -ArgumentList $probeArgs
            if ($r.count -lt 1) { throw "new-shell TabExpansion2 '$Line' returned no matches." }
            $tab.Add($r.tabMs)
            $allocs.Add($r.alloc)
        }
    }
    catch {
        Write-Host ("  {0,-14} {1,-34} FAILED: {2}" -f $Fixture, 'new-shell', $_) -ForegroundColor Yellow
        [pscustomobject]@{ Scenario = "new-shell: TAB '$Line'"; Fixture = $Fixture; Gate = $true; Error = "$_" }
        return
    }
    finally {
        Remove-Item $warmup -Recurse -Force -ErrorAction Ignore
    }

    New-ScenarioResult -Name "new-shell: TAB '$Line'" -Fixture $Fixture -Gate $true -Times $tab -Allocs $allocs
}

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
