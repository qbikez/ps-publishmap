#requires -version 7.0
<#
.SYNOPSIS
    Compares the performance of the two ways a build map can pull in another map:
    an #include directive versus dot-sourcing the child map and nesting its hashtable.
.DESCRIPTION
    Builds two copies of each stored workspace fixture. Both have the same project
    maps; only the root map differs:
      include   - "#include" = @{ p01 = @{ prefix = $true }; ... }   (as stored)
      dotsource - "p01" = . "$PSScriptRoot/p01/.build.map.ps1"; ...  plus _cacheDependsOn,
                  so the discovery cache is rebuilt when a project map changes
    Then runs Invoke-IncludeMethodSuite.ps1 on each copy in fresh pwsh processes,
    alternating the order every round so machine noise hits both sides equally.

    Prints a markdown table with medians of the per-round medians. Report-only: it
    never fails on a difference.
.EXAMPLE
    ./Compare-IncludeMethods.ps1
.EXAMPLE
    ./Compare-IncludeMethods.ps1 -Rounds 1                                   # quick check
.EXAMPLE
    ./Compare-IncludeMethods.ps1 -Fixture workspace-XL -Rounds 1 -ScenarioBudgetSeconds 5   # ~20 min
#>
[CmdletBinding()]
param(
    # workspace-XL is opt-in: one dot-source `qbuild list` there takes about 2 minutes,
    # so a single round of it runs for about 15 minutes.
    [ValidateSet('workspace-M', 'workspace-XL')]
    [string[]]$Fixture = @('workspace-M'),
    [ValidateRange(1, 20)]
    [int]$Rounds = 3,
    [int]$Iterations = 30,
    [double]$ScenarioBudgetSeconds = 10,
    [int]$NewShellIterations = 5,
    [string]$ModulePath = (Join-Path $PSScriptRoot '..\..\configmap.psm1'),
    [string]$OutDir = (Join-Path ([System.IO.Path]::GetTempPath()) "configmap-include-perf-$(Get-Date -Format yyyyMMdd-HHmmss)")
)

$ErrorActionPreference = 'Stop'

$ModulePath = (Resolve-Path $ModulePath).Path
$suite = Join-Path $PSScriptRoot 'Invoke-IncludeMethodSuite.ps1'
$work = Join-Path $OutDir 'work'
$variants = @('include', 'dotsource')

function Get-Median {
    param([double[]]$Values)
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    $mid = [math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2) { return $sorted[$mid] }
    return ($sorted[$mid - 1] + $sorted[$mid]) / 2
}

function ConvertTo-DotSourceRootMap {
    <#
    .SYNOPSIS
        Rewrites an #include root map so each included project is dot-sourced and nested under its name.
    #>
    param([string]$Content)

    $block = [regex]::Match($Content, '(?ms)^(?<indent>[ \t]*)"#include"\s*=\s*(\[ordered\])?@\{\s*$(?<body>.*?)^\k<indent>\}\s*$')
    if (!$block.Success) { throw 'Root map has no "#include" block.' }

    $indent = $block.Groups['indent'].Value
    $names = @([regex]::Matches($block.Groups['body'].Value, '"(?<name>[^"]+)"\s*=') | ForEach-Object { $_.Groups['name'].Value })
    $lines = foreach ($name in $names) { "$indent`"$name`" = . `"`$PSScriptRoot/$name/.build.map.ps1`"" }
    $dependsOn = ($names | ForEach-Object { "`"$_/.build.map.ps1`"" }) -join ', '
    $lines += "${indent}_cacheDependsOn = @($dependsOn)"

    return $Content.Substring(0, $block.Index) + ($lines -join [Environment]::NewLine) + [Environment]::NewLine + $Content.Substring($block.Index + $block.Length)
}

function New-VariantFixture {
    param([string]$Name)

    $stored = Join-Path $work "stored"
    & (Join-Path $PSScriptRoot 'New-PerfFixture.ps1') -Path $stored -Name $Name

    foreach ($variant in $variants) {
        $target = Join-Path $work "$Name\$variant"
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Copy-Item -Path (Join-Path $stored $Name) -Destination $target -Recurse
    }

    $rootMap = Join-Path $work "$Name\dotsource\.build.map.ps1"
    Set-Content -Path $rootMap -Value (ConvertTo-DotSourceRootMap (Get-Content $rootMap -Raw)) -NoNewline
}

function Invoke-Variant {
    param([string]$Name, [string]$Variant, [int]$Round)

    Write-Host "round $Round/$Rounds - $Name / $Variant" -ForegroundColor Cyan
    $out = Join-Path $OutDir "$Name-$Variant-round$Round.json"
    $previousHome = $env:HOME
    try {
        $env:HOME = Join-Path $work "home-$Name-$Variant"
        New-Item -ItemType Directory -Path $env:HOME -Force | Out-Null
        pwsh -NoProfile -NonInteractive -File $suite -ModulePath $ModulePath -Directory (Join-Path $work "$Name\$Variant") `
            -Fixture $Name -Variant $Variant -Iterations $Iterations -ScenarioBudgetSeconds $ScenarioBudgetSeconds `
            -NewShellIterations $NewShellIterations -OutFile $out
        if ($LASTEXITCODE -ne 0) { throw "Suite failed for $Name / $Variant in round $Round." }
    }
    finally {
        $env:HOME = $previousHome
    }
    return Get-Content $out -Raw | ConvertFrom-Json
}

New-Item -ItemType Directory -Path $work -Force | Out-Null
$runs = [System.Collections.Generic.List[object]]::new()
foreach ($name in $Fixture) {
    New-VariantFixture -Name $name

    # Throwaway pass: the first load of freshly written .ps1 files is slowed by antivirus/AMSI scanning.
    foreach ($variant in $variants) {
        $prime = "Import-Module '$ModulePath'; Set-Location '$(Join-Path $work "$name\$variant")'; `$null = qbuild list 6>`$null; `$null = TabExpansion2 'qbuild ' 7"
        pwsh -NoProfile -NonInteractive -Command $prime | Out-Null
    }

    foreach ($round in 1..$Rounds) {
        $order = if ($round % 2) { $variants } else { @($variants[1], $variants[0]) }
        foreach ($variant in $order) { $runs.Add((Invoke-Variant -Name $name -Variant $variant -Round $round)) }
    }
}

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($group in $runs | ForEach-Object { $run = $_; $_.results | ForEach-Object { $_ | Add-Member -NotePropertyName Variant -NotePropertyValue $run.variant -PassThru } } | Group-Object Fixture, Scenario) {
    $first = $group.Group[0]
    $row = [ordered]@{ Fixture = $first.Fixture; Scenario = $first.Scenario }
    foreach ($variant in $variants) {
        $items = @($group.Group | Where-Object Variant -eq $variant)
        $failed = $items | Where-Object Error | Select-Object -First 1
        $row["$($variant)Ms"] = if ($failed) { $null } else { Get-Median @($items.MedianMs) }
        $row["$($variant)KB"] = if ($failed) { $null } else { Get-Median @($items | Where-Object { $null -ne $_.MedianAllocKB } | ForEach-Object MedianAllocKB) }
        $row["$($variant)Error"] = if ($failed) { $failed.Error } else { $null }
    }
    $rows.Add([pscustomobject]$row)
}

$fmt = { param($v) if ($null -eq $v) { '' } else { [string]::Format([cultureinfo]::InvariantCulture, '{0:0.0}', $v) } }
$ratio = {
    param($include, $dotsource)
    if (!$include -or $null -eq $dotsource) { return '' }
    [string]::Format([cultureinfo]::InvariantCulture, '{0:0.00}x', $dotsource / $include)
}
$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine('## #include vs dot-sourced child maps')
[void]$md.AppendLine()
[void]$md.AppendLine("$Rounds round(s), median of per-round medians, $($runs[0].os), pwsh $($runs[0].pwsh). Ratio = dot-source / #include (above 1 = dot-source slower).")
[void]$md.AppendLine()
[void]$md.AppendLine('| Fixture | Scenario | #include ms | dot-source ms | Ratio | #include KB | dot-source KB | Ratio |')
[void]$md.AppendLine('|---|---|--:|--:|--:|--:|--:|--:|')
foreach ($r in $rows) {
    $dotMs = if ($r.dotsourceError) { 'failed' } else { & $fmt $r.dotsourceMs }
    $incMs = if ($r.includeError) { 'failed' } else { & $fmt $r.includeMs }
    [void]$md.AppendLine("| $($r.Fixture) | $($r.Scenario) | $incMs | $dotMs | $(& $ratio $r.includeMs $r.dotsourceMs) | $(& $fmt $r.includeKB) | $(& $fmt $r.dotsourceKB) | $(& $ratio $r.includeKB $r.dotsourceKB) |")
}
foreach ($r in $rows) {
    foreach ($variant in $variants) {
        if ($r."$($variant)Error") {
            [void]$md.AppendLine()
            [void]$md.AppendLine("**$($r.Fixture) / $($r.Scenario) failed with ${variant}:** ``$($r."$($variant)Error")``")
        }
    }
}

$reportPath = Join-Path $OutDir 'include-methods-report.md'
$md.ToString() | Set-Content $reportPath
$rows | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutDir 'include-methods.json')
Write-Host $md.ToString()
Write-Host "report: $reportPath" -ForegroundColor DarkGray
