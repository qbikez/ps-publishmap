#requires -version 7.0

[CmdletBinding()]
param(
    [ValidateRange(5, 10000)]
    [int]$Iterations = 50,

    [ValidateNotNullOrEmpty()]
    [int[]]$EntryCount = @(100, 1000),

    [switch]$AsJson
)

$modulePath = Join-Path $PSScriptRoot '..\configmap.psm1'
Import-Module $modulePath -Force

function New-BenchmarkMap {
    param(
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Count,
        [pscustomobject]$State
    )

    $map = [ordered]@{}
    $command = {
        $State.InvocationCount++
    }

    foreach ($number in 1..$Count) {
        $map["task$number"] = $command
    }

    return $map
}

function New-FileBackedBenchmarkMap {
    param(
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Count,
        [string]$Directory
    )

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $mapFile = Join-Path $Directory '.build.map.ps1'
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('@{')
    foreach ($number in 1..$Count) {
        [void]$builder.AppendLine("    task$number = { param([string]`$Configuration = `"Debug`") }")
    }
    [void]$builder.AppendLine('}')
    Set-Content -Path $mapFile -Value $builder.ToString() -Encoding utf8
    return Import-ConfigMap -Map $mapFile -LookUp:$false
}

function Measure-BenchmarkAction {
    param(
        [string]$Scenario,
        [int]$Entries,
        [int]$Iterations,
        [scriptblock]$Action
    )

    $null = & $Action
    $samples = [System.Collections.Generic.List[double]]::new()
    $allocatedBytes = [System.Collections.Generic.List[long]]::new()

    foreach ($iteration in 1..$Iterations) {
        $before = [GC]::GetTotalAllocatedBytes($true)
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $null = & $Action
        $stopwatch.Stop()

        $samples.Add($stopwatch.Elapsed.TotalMilliseconds)
        $allocatedBytes.Add([GC]::GetTotalAllocatedBytes($true) - $before)
    }

    $orderedSamples = @($samples | Sort-Object)
    $orderedAllocations = @($allocatedBytes | Sort-Object)
    $p95Index = [math]::Ceiling($Iterations * 0.95) - 1

    return [pscustomobject]@{
        Scenario             = $Scenario
        Entries              = $Entries
        Iterations           = $Iterations
        MedianMilliseconds   = [math]::Round($orderedSamples[[int]($Iterations / 2)], 3)
        P95Milliseconds      = [math]::Round($orderedSamples[$p95Index], 3)
        MinimumMilliseconds  = [math]::Round($orderedSamples[0], 3)
        MaximumMilliseconds  = [math]::Round($orderedSamples[-1], 3)
        MedianAllocatedBytes = $orderedAllocations[[int]($Iterations / 2)]
        P95AllocatedBytes    = $orderedAllocations[$p95Index]
    }
}

$module = Get-Module ConfigMap
$discoveryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("configmap-discovery-benchmark-" + [guid]::NewGuid().ToString())

try {
    $results = foreach ($count in $EntryCount) {
        $state = [pscustomobject]@{ InvocationCount = 0 }
        $map = New-BenchmarkMap -Count $count -State $state
        $targetKey = "task$([math]::Floor($count / 2))"

        $lookup = {
            $entries = @(Get-MapEntries $map $targetKey -language build)
            if ($entries.Count -ne 1 -or $entries[0].Key -ne $targetKey) {
                throw "Expected one lookup result for '$targetKey'."
            }
        }

        $completion = {
            $completions = @(Get-EntryCompletion -map $map -language build -wordToComplete '')
            if ($completions.Count -ne $count -or $completions -notcontains $targetKey) {
                throw "Completion results did not match the $count-entry fixture."
            }
        }

        $qbuild = {
            qbuild -map $map $targetKey
        }

        Measure-BenchmarkAction -Scenario 'Get-MapEntries' -Entries $count -Iterations $Iterations -Action $lookup
        Measure-BenchmarkAction -Scenario 'Get-EntryCompletion (no discovery cache)' -Entries $count -Iterations $Iterations -Action $completion
        Measure-BenchmarkAction -Scenario 'qbuild no-op' -Entries $count -Iterations $Iterations -Action $qbuild

        if ($state.InvocationCount -ne ($Iterations + 1)) {
            throw "Expected qbuild to invoke '$targetKey' $($Iterations + 1) times; invoked $($state.InvocationCount) times."
        }

        $fileMap = New-FileBackedBenchmarkMap -Count $count -Directory (Join-Path $discoveryRoot "n$count")
        $cachePath = & $module {
            param($SourceFile)
            Get-ConfigMapDiscoveryCachePath -SourceFile $SourceFile -Language build
        } $fileMap._sourceFile

        $coldCompletion = {
            & $module { Clear-ConfigMapDiscoveryCacheMemory }
            if (Test-Path $cachePath) {
                Remove-Item -Path $cachePath -Force
            }
            $completions = @(Get-EntryCompletion -map $fileMap -language build -wordToComplete '')
            if ($completions.Count -ne $count -or $completions -notcontains $targetKey) {
                throw "Cold discovery-cache completion results did not match the $count-entry fixture."
            }
        }

        $diskHitCompletion = {
            & $module { Clear-ConfigMapDiscoveryCacheMemory }
            $completions = @(Get-EntryCompletion -map $fileMap -language build -wordToComplete '')
            if ($completions.Count -ne $count -or $completions -notcontains $targetKey) {
                throw "Disk-hit discovery-cache completion results did not match the $count-entry fixture."
            }
        }

        $memoryHitCompletion = {
            $completions = @(Get-EntryCompletion -map $fileMap -language build -wordToComplete '')
            if ($completions.Count -ne $count -or $completions -notcontains $targetKey) {
                throw "Memory-hit discovery-cache completion results did not match the $count-entry fixture."
            }
        }

        Measure-BenchmarkAction -Scenario 'Get-EntryCompletion (cold miss + write)' -Entries $count -Iterations $Iterations -Action $coldCompletion
        Measure-BenchmarkAction -Scenario 'Get-EntryCompletion (disk hit)' -Entries $count -Iterations $Iterations -Action $diskHitCompletion
        Measure-BenchmarkAction -Scenario 'Get-EntryCompletion (memory hit)' -Entries $count -Iterations $Iterations -Action $memoryHitCompletion
    }
}
finally {
    if (Test-Path $discoveryRoot) {
        Remove-Item -Path $discoveryRoot -Recurse -Force
    }
}

$includeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("configmap-include-benchmark-" + [guid]::NewGuid().ToString())
try {
    $includeDirectory = Join-Path $includeRoot 'child'
    New-Item -ItemType Directory -Path $includeDirectory -Force | Out-Null
    Set-Content -Path (Join-Path $includeDirectory '.build.map.ps1') -Value @'
@{
    run = { }
}
'@
    $includeMap = @{
        '#include' = @{
            child = @{ prefix = $true }
        }
        _baseDir = $includeRoot
    }
    $withoutOperationCache = {
        & $module {
            param($Map)

            $target = @(Get-MapEntries $Map 'child.run' -language build)[0]
            if (!$target) {
                throw 'Unable to resolve the included benchmark entry.'
            }

            Get-MapEntry $Map 'child.run' -language build | Out-Null
            Invoke-WithEntrySettings -Map $Map -EntryKey 'child.run' -Entry $target.Value -ScriptBlock { }
        } $includeMap
    }

    $withOperationCache = {
        & $module {
            param($Map)

            $context = New-ConfigMapOperationContext
            $target = @(Get-MapEntries $Map 'child.run' -language build -OperationContext $context)[0]
            if (!$target) {
                throw 'Unable to resolve the included benchmark entry.'
            }

            Get-MapEntry $Map 'child.run' -language build -OperationContext $context | Out-Null
            Invoke-WithEntrySettings -Map $Map -EntryKey 'child.run' -Entry $target.Value -OperationContext $context -ScriptBlock { }
        } $includeMap
    }

    $results += Measure-BenchmarkAction -Scenario 'included map without operation cache' -Entries 1 -Iterations $Iterations -Action $withoutOperationCache
    $results += Measure-BenchmarkAction -Scenario 'included map with operation cache' -Entries 1 -Iterations $Iterations -Action $withOperationCache
}
finally {
    if (Test-Path $includeRoot) {
        Remove-Item -Path $includeRoot -Recurse -Force
    }
}

if ($AsJson) {
    $results | ConvertTo-Json
}
else {
    $results
}
