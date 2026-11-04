#requires -version 7.0
<#
.SYNOPSIS
    Prepares map fixtures for the performance suite.
.DESCRIPTION
    workspace-* fixtures model a real workspace: a root .build.map.ps1 that
    #includes one map per project, each with a mix of entry kinds (params,
    nested groups up to 4 levels, steps, options/_template, npm). flat-* is a
    single map of N trivial entries, kept for continuity with the old harness.
    These are stored in test/perf/fixtures and copied to -Path, so every run
    measures the same maps. -Generate rewrites the stored copies from this script.

    samples is never stored: it #includes every git-tracked samples/* build map,
    so it grows with each new sample and always covers current features.
.EXAMPLE
    ./New-PerfFixture.ps1 -Path $env:TEMP/perf -Name workspace-M
.EXAMPLE
    ./New-PerfFixture.ps1 -Generate   # regenerate test/perf/fixtures, then commit
#>
[CmdletBinding()]
param(
    [string]$Path,
    [ValidateSet('workspace-M', 'workspace-XL', 'flat-1k', 'samples')]
    [string[]]$Name = @('workspace-M', 'workspace-XL', 'flat-1k', 'samples'),
    [switch]$Generate,
    [string]$SamplesPath = (Join-Path $PSScriptRoot '..\..\samples')
)

$ErrorActionPreference = 'Stop'
$storedPath = Join-Path $PSScriptRoot 'fixtures'
if (!$Path) {
    if (!$Generate) { throw '-Path is required unless -Generate is used.' }
    $Path = $storedPath
}

$fixtureShapes = @{
    'workspace-M'  = @{ Projects = 5; TasksPerProject = 4 }
    'workspace-XL' = @{ Projects = 40; TasksPerProject = 9 }
}

# Stored fixtures are git-tracked, so format them like the repo-root `qbuild lint -Fix` does;
# otherwise -Generate and lint keep rewriting each other's output.
function Set-FormattedMap {
    param([string]$Path, [string]$Content)

    if (!$script:formatSettings) {
        Import-Module PSScriptAnalyzer
        $allSettings = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\..\..\PSScriptAnalyzerSettings.psd1')
        $formatRules = @('PSUseConsistentIndentation', 'PSUseConsistentWhitespace', 'PSAlignAssignmentStatement')
        $script:formatSettings = @{ IncludeRules = $formatRules; Rules = @{} }
        foreach ($rule in $formatRules) { $script:formatSettings.Rules[$rule] = $allSettings.Rules[$rule] }
    }
    Set-Content -Path $Path -NoNewline -Value (Invoke-Formatter -ScriptDefinition ($Content -replace "`r`n", "`n") -Settings $script:formatSettings)
}

function New-ProjectMap {
    param([string]$Directory, [string]$Project, [int]$Tasks)

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null

    $scripts = [ordered]@{}
    foreach ($n in 1..15) { $scripts["script$n"] = "echo $Project-$n" }
    @{ name = $Project; scripts = $scripts } | ConvertTo-Json | Set-Content (Join-Path $Directory 'package.json')
    "API_URL=http://localhost`nAPI_KEY=dev" | Set-Content (Join-Path $Directory '.env')

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine(@'
[ordered]@{
    "build" = {
        param(
            [ValidateSet('Debug', 'Release')]
            [string]$Configuration = 'Debug',
            [switch]$NoRestore,
            [string]$Framework
        )
        Write-Host "build $Configuration"
    }
    "test" = @{
        exec        = { param([switch]$Watch, [string]$Filter) Write-Host "test" }
        description = "Run tests"
    }
    "tools" = [ordered]@{
        "db" = [ordered]@{
            "migrate" = @{
                exec        = { param([ValidateSet('up', 'down')][string]$Direction = 'up') Write-Host "migrate" }
                description = "Apply database migrations"
            }
            "seed"    = { Write-Host "seed" }
        }
        "fmt" = { param([switch]$Check) Write-Host "fmt" }
    }
    "deploy" = [ordered]@{
        _settings   = @{ process = "steps" }
        description = "Multi-step deploy"
        "package"   = @{ exec = { Write-Host "package" }; check = { $false } }
        "upload"    = { param([ValidateSet('dev', 'prod')][string]$Environment = 'dev') Write-Host "upload" }
        "verify"    = { Write-Host "verify" }
    }
    "env" = [ordered]@{
        _settings   = @{ process = "options" }
        _template   = "dotenv:.env"
        description = "API settings in .env"
        options     = [ordered]@{
            local = [ordered]@{ "API_URL" = "http://localhost"; "API_KEY" = "dev" }
            prod  = [ordered]@{ "API_URL" = "https://api.example"; "API_KEY" = "prod" }
        }
    }
    "web" = [ordered]@{
        _settings   = @{ process = "npm" }
        description = "package.json scripts"
    }
'@)
    foreach ($n in 1..$Tasks) {
        [void]$sb.AppendLine("    `"task$n`" = { param([string]`$Name = 'x$n') Write-Host `"task$n`" }")
    }
    [void]$sb.AppendLine('}')
    Set-FormattedMap -Path (Join-Path $Directory '.build.map.ps1') -Content $sb.ToString()
}

function New-WorkspaceFixture {
    param([string]$Root, [int]$Projects, [int]$TasksPerProject)

    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $names = foreach ($p in 1..$Projects) { 'p{0:d2}' -f $p }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('[ordered]@{')
    [void]$sb.AppendLine('    "clean" = { Write-Host "clean" }')
    [void]$sb.AppendLine('    "restore" = @{ exec = { param([switch]$Force) Write-Host "restore" }; description = "Restore everything" }')
    [void]$sb.AppendLine('    "#include" = [ordered]@{')
    foreach ($name in $names) {
        [void]$sb.AppendLine("        `"$name`" = @{ prefix = `$true }")
        New-ProjectMap -Directory (Join-Path $Root $name) -Project $name -Tasks $TasksPerProject
    }
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('}')
    Set-FormattedMap -Path (Join-Path $Root '.build.map.ps1') -Content $sb.ToString()
}

function New-FlatFixture {
    param([string]$Root, [int]$Count)

    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('@{')
    foreach ($n in 1..$Count) {
        [void]$sb.AppendLine("    task$n = { param([string]`$Configuration = `"Debug`") }")
    }
    [void]$sb.AppendLine('}')
    Set-FormattedMap -Path (Join-Path $Root '.build.map.ps1') -Content $sb.ToString()
}

function New-SamplesFixture {
    param([string]$Root, [string]$Samples)

    $Samples = (Resolve-Path $Samples).Path
    # Tracked files only: local leftovers (obj/, .configmap/, state files) would skew results.
    $files = @(git -C $Samples ls-files)
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed in '$Samples'." }
    foreach ($file in $files) {
        $target = Join-Path $Root $file
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $Samples $file) -Destination $target
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('[ordered]@{')
    [void]$sb.AppendLine('    "#include" = [ordered]@{')
    foreach ($dir in Get-ChildItem $Root -Directory | Sort-Object Name) {
        if (Test-Path (Join-Path $dir.FullName '.build.map.ps1')) {
            [void]$sb.AppendLine("        `"$($dir.Name)`" = @{ prefix = `$true }")
        }
    }
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('}')
    Set-Content -Path (Join-Path $Root '.build.map.ps1') -Value $sb.ToString()
}

foreach ($fixture in $Name) {
    $root = Join-Path $Path $fixture
    if ($fixture -eq 'samples') {
        if (!$Generate) { New-SamplesFixture -Root $root -Samples $SamplesPath }
        continue
    }

    if (!$Generate) {
        $stored = Join-Path $storedPath $fixture
        if (!(Test-Path $stored)) { throw "Stored fixture '$stored' not found; run with -Generate." }
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Copy-Item -Path $stored -Destination $Path -Recurse -Force
        Get-ChildItem $root -Recurse -Directory -Force -Filter '.configmap' | Remove-Item -Recurse -Force
        continue
    }

    if (Test-Path $root) { Remove-Item $root -Recurse -Force }
    if ($fixture -eq 'flat-1k') {
        New-FlatFixture -Root $root -Count 1000
    }
    else {
        $shape = $fixtureShapes[$fixture]
        New-WorkspaceFixture -Root $root -Projects $shape.Projects -TasksPerProject $shape.TasksPerProject
    }
}
