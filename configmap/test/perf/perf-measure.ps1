# Measurement helpers shared by the perf suites. Dot-source them into a suite that defines
# $Iterations, $ScenarioBudgetSeconds, $NewShellIterations, $ImportIterations, $ModulePath,
# $ProfileDir, $ProfileTop and $profileReport.

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
