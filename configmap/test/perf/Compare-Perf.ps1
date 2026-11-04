#requires -version 7.0
<#
.SYNOPSIS
    A/B performance comparison of two configmap revisions on the same machine.
.DESCRIPTION
    Checks out -Base (and -Head, or uses the working tree) as git worktrees, then
    runs this checkout's Invoke-PerfSuite.ps1 against each module in fresh pwsh
    processes, alternating the order every round so machine noise hits both sides
    equally. Each side gets its own fixture copy and HOME, so discovery caches
    never leak between them.

    Prints a markdown table and exits 1 when a gated scenario regresses:
      time:  head slower by more than -TimeThresholdPercent AND -TimeThresholdMs in
             every round, needs -Rounds 2+ (paired per round; timings are noisy,
             allocations are not)
      alloc: median allocations up by more than -AllocThresholdPercent AND -AllocThresholdKB
.EXAMPLE
    ./Compare-Perf.ps1 -Base master
.EXAMPLE
    ./Compare-Perf.ps1 -Base master -Fixture workspace-M -Rounds 1   # quick local check
#>
[CmdletBinding()]
param(
    [string]$Base = 'master',
    # Empty: the current working tree, including uncommitted changes.
    [string]$Head,
    [ValidateRange(1, 20)]
    [int]$Rounds = 3,
    [int]$Iterations = 30,
    [double]$ScenarioBudgetSeconds = 10,
    [int]$NewShellIterations = 5,
    [ValidateSet('workspace-M', 'workspace-XL', 'flat-1k', 'samples')]
    [string[]]$Fixture = @('workspace-M', 'workspace-XL', 'flat-1k', 'samples'),
    [double]$TimeThresholdPercent = 25,
    [double]$TimeThresholdMs = 5,
    [double]$AllocThresholdPercent = 10,
    [double]$AllocThresholdKB = 64,
    [string]$OutDir = (Join-Path ([System.IO.Path]::GetTempPath()) "configmap-perf-$(Get-Date -Format yyyyMMdd-HHmmss)"),
    [switch]$NoFail
)

$ErrorActionPreference = 'Stop'

$moduleDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$repoRoot = (git -C $moduleDir rev-parse --show-toplevel).Trim()
$modulePrefix = (git -C $moduleDir rev-parse --show-prefix).Trim()
$suite = Join-Path $PSScriptRoot 'Invoke-PerfSuite.ps1'
$work = Join-Path $OutDir 'work'
New-Item -ItemType Directory -Path $work -Force | Out-Null

function Get-Median {
    param([double[]]$Values)
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    $mid = [math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2) { return $sorted[$mid] }
    return ($sorted[$mid - 1] + $sorted[$mid]) / 2
}

function New-Side {
    param([string]$Name, [string]$Ref)

    $sha = if ($Ref) { (git -C $repoRoot rev-parse --short $Ref).Trim() } else { "$((git -C $repoRoot rev-parse --short HEAD).Trim())+wt" }
    if ($LASTEXITCODE -ne 0) { throw "Unknown ref '$Ref'." }

    $modulePath = Join-Path $moduleDir 'configmap.psm1'
    $worktree = $null
    if ($Ref) {
        $worktree = Join-Path $work "src-$Name"
        git -C $repoRoot worktree add --detach --force $worktree $Ref 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git worktree add failed for '$Ref'." }
        $modulePath = Join-Path $worktree (Join-Path $modulePrefix 'configmap.psm1')
    }

    $fixtures = Join-Path $work "fixtures-$Name"
    & (Join-Path $PSScriptRoot 'New-PerfFixture.ps1') -Path $fixtures -Name $Fixture

    $userHome = Join-Path $work "home-$Name"
    New-Item -ItemType Directory -Path $userHome -Force | Out-Null

    # Throwaway pass: the first load of freshly written .ps1 files is slowed by
    # antivirus/AMSI scanning, which would otherwise land in round 1.
    $prime = "Import-Module '$modulePath'; Get-ChildItem '$fixtures' -Directory | ForEach-Object { Set-Location `$_.FullName; `$null = qbuild list 6>`$null; `$null = TabExpansion2 'qbuild ' 7 }"
    $previousHome = $env:HOME
    try {
        $env:HOME = $userHome
        pwsh -NoProfile -NonInteractive -Command $prime | Out-Null
    }
    finally {
        $env:HOME = $previousHome
    }

    [pscustomobject]@{
        Name       = $Name
        Ref        = if ($Ref) { $Ref } else { 'working tree' }
        Sha        = $sha
        ModulePath = $modulePath
        Worktree   = $worktree
        Fixtures   = $fixtures
        Home       = $userHome
        Runs       = [System.Collections.Generic.List[object]]::new()
    }
}

function Invoke-Side {
    param($Side, [int]$Round)

    Write-Host "round $Round/$Rounds - $($Side.Name) ($($Side.Ref) @ $($Side.Sha))" -ForegroundColor Cyan
    $out = Join-Path $OutDir "$($Side.Name)-round$Round.json"
    $previousHome = $env:HOME
    try {
        $env:HOME = $Side.Home
        pwsh -NoProfile -NonInteractive -File $suite -ModulePath $Side.ModulePath -FixtureRoot $Side.Fixtures `
            -Iterations $Iterations -ScenarioBudgetSeconds $ScenarioBudgetSeconds -NewShellIterations $NewShellIterations `
            -Label "$($Side.Name)@$($Side.Sha)" -OutFile $out
        if ($LASTEXITCODE -ne 0) { throw "Perf suite failed for $($Side.Name) in round $Round." }
    }
    finally {
        $env:HOME = $previousHome
    }
    $Side.Runs.Add((Get-Content $out -Raw | ConvertFrom-Json))
}

function Get-SideSummary {
    param($Side)

    $summary = [ordered]@{}
    foreach ($row in $Side.Runs.results) {
        $key = "$($row.Fixture)|$($row.Scenario)"
        if (!$summary.Contains($key)) {
            $summary[$key] = [pscustomobject]@{ Fixture = $row.Fixture; Scenario = $row.Scenario; Gate = $row.Gate; Ms = @(); KB = @(); Error = $null }
        }
        $item = $summary[$key]
        if ($row.Error) { $item.Error = $row.Error; continue }
        $item.Ms += [double]$row.MedianMs
        if ($null -ne $row.MedianAllocKB) { $item.KB += [double]$row.MedianAllocKB }
    }
    foreach ($item in $summary.Values) {
        $item | Add-Member -NotePropertyName MedianMs -NotePropertyValue (Get-Median $item.Ms)
        $item | Add-Member -NotePropertyName MedianKB -NotePropertyValue (Get-Median $item.KB)
    }
    return $summary
}

function Test-SlowerEveryRound {
    param([string]$Key, $Slow, $Fast)

    $pairs = 0
    for ($i = 0; $i -lt [math]::Min($Slow.Runs.Count, $Fast.Runs.Count); $i++) {
        $s = $Slow.Runs[$i].results | Where-Object { "$($_.Fixture)|$($_.Scenario)" -eq $Key -and !$_.Error }
        $f = $Fast.Runs[$i].results | Where-Object { "$($_.Fixture)|$($_.Scenario)" -eq $Key -and !$_.Error }
        if (!$s -or !$f) { continue }
        if (!(Test-Worse $f.MedianMs $s.MedianMs $TimeThresholdPercent $TimeThresholdMs)) { return $false }
        $pairs++
    }
    # One round cannot tell a regression from a noisy process.
    return $pairs -ge 2
}

function Format-Delta {
    param($BaseValue, $HeadValue)
    if ($null -eq $BaseValue -or $null -eq $HeadValue -or $BaseValue -eq 0) { return '' }
    $pct = ($HeadValue - $BaseValue) / $BaseValue * 100
    return [string]::Format([cultureinfo]::InvariantCulture, '{0:+0;-0;0}%', $pct)
}

function Test-Worse {
    param($BaseValue, $HeadValue, [double]$Percent, [double]$Absolute)
    if ($null -eq $BaseValue -or $null -eq $HeadValue -or $BaseValue -eq 0) { return $false }
    return ($HeadValue - $BaseValue) -gt $Absolute -and (($HeadValue - $BaseValue) / $BaseValue * 100) -gt $Percent
}

$sides = @()
try {
    $baseSide = New-Side -Name 'base' -Ref $Base
    $headSide = New-Side -Name 'head' -Ref $Head
    $sides = @($baseSide, $headSide)

    foreach ($round in 1..$Rounds) {
        $order = if ($round % 2) { @($baseSide, $headSide) } else { @($headSide, $baseSide) }
        foreach ($side in $order) { Invoke-Side -Side $side -Round $round }
    }
}
finally {
    foreach ($side in $sides) {
        if ($side.Worktree) { git -C $repoRoot worktree remove --force $side.Worktree 2>&1 | Out-Null }
    }
}

$baseSummary = Get-SideSummary $baseSide
$headSummary = Get-SideSummary $headSide

$rows = [System.Collections.Generic.List[object]]::new()
$regressions = 0
foreach ($key in $headSummary.Keys) {
    $h = $headSummary[$key]
    $b = $baseSummary[$key]
    $status = 'ok'
    if ($h.Error) {
        $status = 'head failed'
    }
    elseif (!$b -or $b.Error) {
        $status = 'new'
    }
    else {
        $slower = Test-SlowerEveryRound -Key $key -Slow $headSide -Fast $baseSide
        $moreAlloc = Test-Worse $b.MedianKB $h.MedianKB $AllocThresholdPercent $AllocThresholdKB
        $faster = Test-SlowerEveryRound -Key $key -Slow $baseSide -Fast $headSide
        $status = if ($slower -and $moreAlloc) { 'slower, more alloc' }
        elseif ($slower) { 'slower' }
        elseif ($moreAlloc) { 'more alloc' }
        elseif ($faster) { 'faster' }
        else { 'ok' }
    }
    $isRegression = $status -in 'head failed', 'slower, more alloc', 'slower', 'more alloc'
    if ($isRegression -and $h.Gate) { $regressions++ }

    $icon = if ($isRegression -and $h.Gate) { '🔴' } elseif ($isRegression) { '⚠️' } elseif ($status -eq 'faster') { '🟢' } else { '' }
    $rows.Add([pscustomobject]@{
            Fixture  = $h.Fixture
            Scenario = $h.Scenario + $(if (!$h.Gate) { ' *' })
            BaseMs   = $b.MedianMs
            HeadMs   = $h.MedianMs
            DeltaMs  = Format-Delta $b.MedianMs $h.MedianMs
            BaseKB   = $b.MedianKB
            HeadKB   = $h.MedianKB
            DeltaKB  = Format-Delta $b.MedianKB $h.MedianKB
            Status   = "$icon $status".Trim()
            Error    = $h.Error
        })
}

$fmt = { param($v) if ($null -eq $v) { '' } else { [string]::Format([cultureinfo]::InvariantCulture, '{0:0.0}', $v) } }
$md = [System.Text.StringBuilder]::new()
$verdict = if ($regressions) { "🔴 $regressions gated regression(s)" } else { '✅ no gated regressions' }
[void]$md.AppendLine("## qbuild performance: $verdict")
[void]$md.AppendLine()
[void]$md.AppendLine("base ``$($baseSide.Ref)`` @ $($baseSide.Sha) vs head ``$($headSide.Ref)`` @ $($headSide.Sha) - $Rounds round(s), median of per-round medians, $($headSide.Runs[0].os), pwsh $($headSide.Runs[0].pwsh)")
[void]$md.AppendLine()
[void]$md.AppendLine('| Fixture | Scenario | Base ms | Head ms | Δ time | Base KB | Head KB | Δ alloc | Status |')
[void]$md.AppendLine('|---|---|--:|--:|--:|--:|--:|--:|---|')
foreach ($r in $rows) {
    [void]$md.AppendLine("| $($r.Fixture) | $($r.Scenario) | $(& $fmt $r.BaseMs) | $(& $fmt $r.HeadMs) | $($r.DeltaMs) | $(& $fmt $r.BaseKB) | $(& $fmt $r.HeadKB) | $($r.DeltaKB) | $($r.Status) |")
}
[void]$md.AppendLine()
[void]$md.AppendLine("Regression = time +$TimeThresholdPercent% and +$TimeThresholdMs ms in every round, or median allocations +$AllocThresholdPercent% and +$AllocThresholdKB KB. ``*`` = internal helper, report-only.")
foreach ($r in $rows | Where-Object Error) {
    [void]$md.AppendLine()
    [void]$md.AppendLine("**$($r.Fixture) / $($r.Scenario) failed on head:** ``$($r.Error)``")
}

$reportPath = Join-Path $OutDir 'perf-report.md'
$md.ToString() | Set-Content $reportPath
$rows | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutDir 'perf-compare.json')
Write-Host $md.ToString()
Write-Host "report: $reportPath" -ForegroundColor DarkGray

if ($regressions -and !$NoFail) { exit 1 }
