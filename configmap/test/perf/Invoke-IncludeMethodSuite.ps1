#requires -version 7.0
<#
.SYNOPSIS
    Measures qbuild on one workspace fixture whose root map pulls in its project maps
    either with #include or by dot-sourcing them. Emits JSON.
.DESCRIPTION
    Run by Compare-IncludeMethods.ps1 in a fresh pwsh process per fixture, variant and
    round. Both variants expose the projects as p01..pNN, so the same command lines
    work on both. Cache states are the same as in Invoke-PerfSuite.ps1:
      warm      - repeated call in a loaded session
      edited    - a project map was just touched, so the discovery cache is rebuilt
      new-shell - fresh pwsh: module import + first command
.EXAMPLE
    ./Invoke-IncludeMethodSuite.ps1 -Directory $env:TEMP/x/workspace-M/dotsource -Fixture workspace-M -Variant dotsource
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Directory,
    [Parameter(Mandatory = $true)]
    [string]$Fixture,
    [Parameter(Mandatory = $true)]
    [ValidateSet('include', 'dotsource')]
    [string]$Variant,
    [string]$ModulePath = (Join-Path $PSScriptRoot '..\..\configmap.psm1'),
    [ValidateRange(3, 10000)]
    [int]$Iterations = 30,
    [double]$ScenarioBudgetSeconds = 10,
    [ValidateRange(1, 1000)]
    [int]$NewShellIterations = 8,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

Get-ChildItem env: | Where-Object Name -like 'QCONF_*' | ForEach-Object { Remove-Item "env:$($_.Name)" }

. (Join-Path $PSScriptRoot 'perf-measure.ps1')

$ModulePath = (Resolve-Path $ModulePath).Path
$Directory = (Resolve-Path $Directory).Path
Import-Module $ModulePath -Force

function Measure-NewShellRun {
    <#
    .SYNOPSIS
        Times `qbuild <entry>` as the first command of a fresh pwsh, like a CLI invocation.
    #>
    param([string]$Fixture, [string]$Directory, [string]$Entry)

    $probe = {
        param($ModulePath, $Directory, $Entry)
        Get-ChildItem env: | Where-Object Name -like 'QCONF_*' | ForEach-Object { Remove-Item "env:$($_.Name)" }
        Import-Module $ModulePath
        Set-Location $Directory
        $before = [GC]::GetTotalAllocatedBytes($true)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = qbuild $Entry *>&1
        $runMs = $sw.Elapsed.TotalMilliseconds
        $alloc = [GC]::GetTotalAllocatedBytes($true) - $before
        @{ runMs = $runMs; alloc = $alloc } | ConvertTo-Json -Compress
    }
    $command = "& { $probe } '$ModulePath' '$Directory' '$Entry'"
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
    $name = "new-shell: qbuild $Entry"

    $times = [System.Collections.Generic.List[double]]::new()
    $allocs = [System.Collections.Generic.List[long]]::new()
    try {
        $null = pwsh -NoProfile -NonInteractive -EncodedCommand $encoded
        foreach ($i in 1..$NewShellIterations) {
            $r = pwsh -NoProfile -NonInteractive -EncodedCommand $encoded | Select-Object -Last 1 | ConvertFrom-Json
            $times.Add($r.runMs)
            $allocs.Add($r.alloc)
        }
    }
    catch {
        Write-Host ("  {0,-14} {1,-34} FAILED: {2}" -f $Fixture, $name, $_) -ForegroundColor Yellow
        return [pscustomobject]@{ Scenario = $name; Fixture = $Fixture; Gate = $false; Error = "$_" }
    }

    New-ScenarioResult -Name $name -Fixture $Fixture -Gate $false -Times $times -Allocs $allocs
}

$results = [System.Collections.Generic.List[object]]::new()
$startLocation = Get-Location
try {
    Set-Location $Directory
    $rootMap = Join-Path $Directory '.build.map.ps1'
    $childMap = Join-Path $Directory 'p03\.build.map.ps1'
    $touch = { (Get-Item $childMap).LastWriteTimeUtc = [datetime]::UtcNow }.GetNewClosure()

    $results.Add((Measure-Scenario -Name 'load root map' -Fixture $Fixture -Gate $false -Action {
                Import-ConfigMap -Map $rootMap -LookUp:$false
            }))

    $list = { qbuild list 6>&1 | Out-String }
    $results.Add((Measure-Scenario -Name 'list (warm)' -Fixture $Fixture -Action $list))
    $results.Add((Measure-Scenario -Name 'list (edited)' -Fixture $Fixture -Action $list -Setup $touch))

    $tabs = [ordered]@{
        'TAB entry'       = 'qbuild '
        'TAB nested'      = 'qbuild p03.tools.db.'
        'TAB param name'  = 'qbuild p03.build -'
        'TAB param value' = 'qbuild p03.build -Configuration '
        'TAB pkg script'  = 'qbuild p03.web '
    }
    foreach ($kv in $tabs.GetEnumerator()) {
        $results.Add((Measure-Scenario -Name "$($kv.Key) (warm)" -Fixture $Fixture -Action { param($l) Measure-Tab $l } -ArgumentList $kv.Value))
    }
    $results.Add((Measure-Scenario -Name 'TAB entry (edited)' -Fixture $Fixture -Action { Measure-Tab 'qbuild ' } -Setup $touch))

    $results.Add((Measure-Scenario -Name 'run p03.task1 (warm)' -Fixture $Fixture -Action { qbuild p03.task1 *>&1 | Out-Null }))

    foreach ($r in Measure-NewShell -Fixture $Fixture -Directory $Directory -Line 'qbuild ') { $results.Add($r) }
    $results.Add((Measure-NewShellRun -Fixture $Fixture -Directory $Directory -Entry 'p03.task1'))
}
finally {
    Set-Location $startLocation
}

$report = [ordered]@{
    variant    = $Variant
    fixture    = $Fixture
    pwsh       = $PSVersionTable.PSVersion.ToString()
    os         = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    iterations = $Iterations
    results    = $results
}

if ($OutFile) {
    $report | ConvertTo-Json -Depth 5 | Set-Content $OutFile
}
else {
    $results | Format-Table -AutoSize | Out-String | Write-Host
}
