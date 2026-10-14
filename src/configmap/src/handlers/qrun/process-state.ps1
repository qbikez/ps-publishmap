#requires -version 7.0

function Get-ProcessReservedKeys {
    return (Get-MapLanguage build).reservedKeys
}

function Get-ProcessStepNames {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ProcessEntry
    )

    $reservedKeys = Get-ProcessReservedKeys

    if ($ProcessEntry.exec -is [array] -and $ProcessEntry.exec.Count -gt 0) {
        return @($ProcessEntry.exec)
    }

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($kvp in $ProcessEntry.GetEnumerator()) {
        if ($kvp.Key -in $reservedKeys) { continue }
        if ($kvp.Value -is [scriptblock]) {
            $names.Add([string]$kvp.Key)
            continue
        }
        if ($kvp.Value -is [System.Collections.IDictionary] -and (Get-EntryHasExec $kvp.Value)) {
            $names.Add([string]$kvp.Key)
        }
    }
    return @($names)
}

function Get-ProcessStepEntry {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ProcessEntry,
        [Parameter(Mandatory = $true)]
        [string]$StepName
    )

    if ($ProcessEntry.Keys -notcontains $StepName) {
        throw "Step '$StepName' not found in process"
    }
    return $ProcessEntry[$StepName]
}

function Resolve-ProcessTarget {
    <#
    .SYNOPSIS
        Resolve a qrun entry path to a process and optional implied step.
        Supports qbuild-style paths: process, process.step, process.all
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        [Parameter(Mandatory = $true)]
        [string]$Entry,
        $OperationContext
    )

    $entryKey = $Entry
    $impliedStep = $null

    if ($entryKey -match '^(.*)\.all$') {
        $entryKey = $Matches[1]
    }

    $resolved = Get-MapEntry $Map $entryKey -language "build" -OperationContext $OperationContext
    if ($null -eq $resolved) {
        throw "Process '$Entry' not found. Run 'qrun list' to see available processes."
    }

    $stepNames = @()
    if ($resolved -is [System.Collections.IDictionary]) {
        $stepNames = @(Get-ProcessStepNames $resolved)
    }

    if ($stepNames.Count -gt 0) {
        return [pscustomobject]@{
            ProcessKey   = $entryKey
            ProcessEntry = $resolved
            StepNames    = $stepNames
            ImpliedStep  = $null
        }
    }

    # Leaf path like process.step — walk up to the parent process
    if ($entryKey -notmatch '\.') {
        if ($resolved -is [scriptblock]) {
            throw "Entry '$Entry' is a single scriptblock. Define an ordered hashtable of steps for qrun."
        }
        throw "Process '$Entry' has no steps."
    }

    $lastDot = $entryKey.LastIndexOf('.')
    $processKey = $entryKey.Substring(0, $lastDot)
    $impliedStep = $entryKey.Substring($lastDot + 1)

    $processEntry = Get-MapEntry $Map $processKey -language "build" -OperationContext $OperationContext
    if ($null -eq $processEntry -or $processEntry -isnot [System.Collections.IDictionary]) {
        throw "Process '$Entry' not found. Run 'qrun list' to see available processes."
    }

    $stepNames = @(Get-ProcessStepNames $processEntry)
    if ($impliedStep -notin $stepNames) {
        throw "Step '$impliedStep' not found in process '$processKey'. Available steps: $($stepNames -join ', ')"
    }

    return [pscustomobject]@{
        ProcessKey   = $processKey
        ProcessEntry = $processEntry
        StepNames    = $stepNames
        ImpliedStep  = $impliedStep
    }
}

function Get-ProcessStateRoot {
    param(
        [string]$BaseDir = (Get-Location).Path,
        [string]$MapFile
    )

    $stateRoot = Join-Path $BaseDir '.configmap' 'process'
    if ($MapFile) {
        $mapLeaf = [System.IO.Path]::GetFileNameWithoutExtension((Split-Path -Leaf $MapFile))
        $safeMap = ($mapLeaf -replace '[<>:"/\\|?*]', '_').Trim()
        if ($safeMap) {
            $stateRoot = Join-Path $stateRoot $safeMap
        }
    }
    return $stateRoot
}

function Get-ProcessStatePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessKey,
        [string]$BaseDir = (Get-Location).Path,
        [string]$MapFile
    )

    $safeKey = ($ProcessKey -replace '[<>:"/\\|?*]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safeKey)) {
        $safeKey = 'process'
    }

    $stateRoot = Get-ProcessStateRoot -BaseDir $BaseDir -MapFile $MapFile
    return Join-Path $stateRoot "$safeKey.state.json"
}

function Get-ProcessStateFiles {
    param(
        [string]$BaseDir = (Get-Location).Path,
        [string]$MapFile,
        [string]$ProcessKey
    )

    $stateRoot = Get-ProcessStateRoot -BaseDir $BaseDir -MapFile $MapFile
    if (!(Test-Path -LiteralPath $stateRoot -PathType Container)) {
        return @()
    }

    if ($ProcessKey) {
        $path = Get-ProcessStatePath -ProcessKey $ProcessKey -BaseDir $BaseDir -MapFile $MapFile
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return @(Get-Item -LiteralPath $path)
        }
        return @()
    }

    return @(Get-ChildItem -LiteralPath $stateRoot -Filter '*.state.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
}

function Get-ProcessMapCatalog {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        $OperationContext,
        # When set, only entries with _settings.process=<name>. When IncludeImplicit,
        # also entries without that setting (standalone .process.map.ps1 via qrun).
        [string]$ProcessName,
        [switch]$IncludeImplicit
    )

    $reservedKeys = Get-ProcessReservedKeys
    $catalog = [System.Collections.Generic.List[object]]::new()

    foreach ($kvp in $Map.GetEnumerator()) {
        $key = [string]$kvp.Key
        if ($key -in $reservedKeys) { continue }
        if ($key.StartsWith('_')) { continue }
        if ($kvp.Value -isnot [System.Collections.IDictionary]) { continue }

        if ($ProcessName) {
            $entryProcess = Get-EntryProcess $kvp.Value -Default ''
            $matchesExplicit = ($entryProcess -eq $ProcessName)
            $matchesImplicit = ($IncludeImplicit -and -not $entryProcess)
            if (-not $matchesExplicit -and -not $matchesImplicit) {
                continue
            }
        }

        try {
            $target = Resolve-ProcessTarget -Map $Map -Entry $key -OperationContext $OperationContext
        }
        catch {
            continue
        }

        if ($target.ImpliedStep -or $target.StepNames.Count -eq 0) { continue }

        $description = ''
        if ($target.ProcessEntry.description) {
            $description = [string]$target.ProcessEntry.description
        }

        $catalog.Add([pscustomobject]@{
                ProcessKey   = $target.ProcessKey
                ProcessEntry = $target.ProcessEntry
                StepNames    = @($target.StepNames)
                Description  = $description
            })
    }

    return @($catalog)
}

function Invoke-ProcessStateCommand {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('show', 'clean')]
        [string]$Action,
        [string]$ProcessKey,
        [System.Collections.IDictionary]$Map,
        [string]$BaseDir = (Get-Location).Path,
        [string]$MapFile,
        $OperationContext,
        [string]$Title = 'QRUN',
        [string]$ProcessName,
        [switch]$IncludeImplicit
    )

    if ($Action -eq 'clean') {
        $files = @(Get-ProcessStateFiles -BaseDir $BaseDir -MapFile $MapFile -ProcessKey $ProcessKey)
        if ($files.Count -eq 0) {
            $scope = if ($ProcessKey) { "for process '$ProcessKey'" } else { '' }
            Write-Host "No process state to clean $scope".Trim() -ForegroundColor DarkGray
            return
        }

        foreach ($file in $files) {
            Remove-Item -LiteralPath $file.FullName -Force
            Write-Host "Removed $($file.FullName)" -ForegroundColor Yellow
        }

        $stateRoot = Get-ProcessStateRoot -BaseDir $BaseDir -MapFile $MapFile
        if ((Test-Path -LiteralPath $stateRoot -PathType Container) -and -not (Get-ChildItem -LiteralPath $stateRoot -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $stateRoot -Force -ErrorAction SilentlyContinue
        }
        return
    }

    # show — catalog from the map (like list), markers from persisted state
    if (!$Map) {
        throw "No process map file found. Run 'qrun !init' to create one, or provide -map."
    }

    $catalogParams = @{
        Map              = $Map
        OperationContext = $OperationContext
    }
    if ($ProcessName) {
        $catalogParams.ProcessName = $ProcessName
        $catalogParams.IncludeImplicit = $IncludeImplicit
    }
    $catalog = @(Get-ProcessMapCatalog @catalogParams)
    if ($ProcessKey) {
        $catalog = @($catalog | Where-Object { $_.ProcessKey -eq $ProcessKey })
        if ($catalog.Count -eq 0) {
            # allow process.step filter by resolving to parent process
            $target = Resolve-ProcessTarget -Map $Map -Entry $ProcessKey -OperationContext $OperationContext
            $catalog = @(Get-ProcessMapCatalog @catalogParams | Where-Object { $_.ProcessKey -eq $target.ProcessKey })
        }
        if ($catalog.Count -eq 0) {
            throw "Process '$ProcessKey' not found. Run 'qrun list' to see available processes."
        }
    }

    if ($catalog.Count -eq 0) {
        Write-Host ""
        Write-Host $Title -ForegroundColor Cyan
        Write-Host "No processes found in the map." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "Process state" -ForegroundColor Gray
    Write-Host ""
    Write-Host "PROCESSES:" -ForegroundColor Yellow

    foreach ($item in $catalog) {
        $statePath = Get-ProcessStatePath -ProcessKey $item.ProcessKey -BaseDir $BaseDir -MapFile $MapFile
        $state = Read-ProcessState -StatePath $statePath -ProcessKey $item.ProcessKey -StepNames $item.StepNames -MapFile $MapFile
        Write-ProcessStatus -ProcessKey $item.ProcessKey -StepNames $item.StepNames -State $state -Description $item.Description
    }
}

function New-ProcessState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessKey,
        [string[]]$StepNames = @(),
        [string]$MapFile
    )

    $steps = [ordered]@{}
    foreach ($name in $StepNames) {
        $steps[$name] = [ordered]@{
            status     = 'Pending'
            startedAt  = $null
            finishedAt = $null
            error      = $null
        }
    }

    return [ordered]@{
        version   = 1
        process   = $ProcessKey
        mapFile   = $MapFile
        updatedAt = (Get-Date).ToString('o')
        steps     = $steps
    }
}

function Read-ProcessState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath,
        [Parameter(Mandatory = $true)]
        [string]$ProcessKey,
        [string[]]$StepNames = @(),
        [string]$MapFile
    )

    if (!(Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        return New-ProcessState -ProcessKey $ProcessKey -StepNames $StepNames -MapFile $MapFile
    }

    try {
        $raw = Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not read process state '$StatePath'; starting fresh. $_"
        return New-ProcessState -ProcessKey $ProcessKey -StepNames $StepNames -MapFile $MapFile
    }

    $state = New-ProcessState -ProcessKey $ProcessKey -StepNames $StepNames -MapFile $MapFile
    if ($raw.steps) {
        foreach ($name in $StepNames) {
            $existing = $raw.steps.$name
            if ($null -eq $existing) { continue }
            $state.steps[$name] = [ordered]@{
                status     = if ($existing.status) { [string]$existing.status } else { 'Pending' }
                startedAt  = $existing.startedAt
                finishedAt = $existing.finishedAt
                error      = $existing.error
            }
        }
    }
    return $state
}

function Write-ProcessState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath,
        [Parameter(Mandatory = $true)]
        $State
    )

    $State.updatedAt = (Get-Date).ToString('o')
    $dir = Split-Path -Parent $StatePath
    if (!(Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    }

    $json = $State | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $StatePath -Value $json -Encoding utf8 -ErrorAction Stop
}

function Reset-ProcessState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        Remove-Item -LiteralPath $StatePath -Force
    }
}

function Get-ProcessStepsToRun {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$StepNames,
        [string]$FromStep,
        [switch]$Follow
    )

    if ($Follow -and -not $FromStep) {
        throw "-Follow requires a step path (e.g. qrun bootstrap.restore -Follow)"
    }

    if (-not $FromStep) {
        return @($StepNames)
    }

    if ($FromStep -notin $StepNames) {
        throw "Step '$FromStep' not found. Available steps: $($StepNames -join ', ')"
    }

    if ($Follow) {
        $idx = [array]::IndexOf($StepNames, $FromStep)
        return @($StepNames[$idx..($StepNames.Count - 1)])
    }

    return @($FromStep)
}

function Assert-ProcessPriorSteps {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$StepNames,
        [Parameter(Mandatory = $true)]
        [string]$FromStep,
        [Parameter(Mandatory = $true)]
        $State,
        [switch]$Force
    )

    if ($FromStep -notin $StepNames) {
        throw "Step '$FromStep' not found. Available steps: $($StepNames -join ', ')"
    }

    $idx = [array]::IndexOf($StepNames, $FromStep)
    if ($idx -le 0) {
        return @()
    }

    $prior = @($StepNames[0..($idx - 1)])
    $incomplete = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $prior) {
        $status = if ($State.steps[$name]) { [string]$State.steps[$name].status } else { 'Pending' }
        if ($status -ne 'Succeeded') {
            $incomplete.Add("$name ($status)")
        }
    }

    if ($incomplete.Count -eq 0) {
        return @()
    }

    if (-not $Force) {
        throw "Cannot start at '$FromStep' — prior steps are incomplete: $($incomplete -join ', '). Re-run from the beginning, or use -Force to skip them."
    }

    # Names of prior steps being skipped due to -Force
    $forcedSkip = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $prior) {
        $status = if ($State.steps[$name]) { [string]$State.steps[$name].status } else { 'Pending' }
        if ($status -ne 'Succeeded') {
            $forcedSkip.Add($name)
        }
    }
    return @($forcedSkip)
}

function Get-ProcessDynamicParam {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        [Parameter(Mandatory = $true)]
        [string]$ProcessKey,
        [switch]$Follow
    )

    try {
        $target = Resolve-ProcessTarget -Map $Map -Entry $ProcessKey
    }
    catch {
        return New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    }

    $processEntry = $target.ProcessEntry
    $stepNames = @($target.StepNames)
    if ($stepNames.Count -eq 0) {
        return New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    }

    try {
        $selected = Get-ProcessStepsToRun -StepNames $stepNames -FromStep $target.ImpliedStep -Follow:$Follow
    }
    catch {
        $selected = $stepNames
    }

    $merged = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    foreach ($stepName in $selected) {
        $stepEntry = Get-ProcessStepEntry -ProcessEntry $processEntry -StepName $stepName
        try {
            $command = Get-EntryCommand $stepEntry "exec"
        }
        catch {
            continue
        }
        if ($command -isnot [scriptblock]) { continue }

        $entryContext = if ($stepEntry -is [System.Collections.IDictionary]) { $stepEntry } else { $null }
        $stepParams = Get-ScriptArgs $command -entry $entryContext
        foreach ($paramName in $stepParams.Keys) {
            if (-not $merged.ContainsKey($paramName)) {
                $merged.Add($paramName, $stepParams[$paramName])
            }
        }
    }

    return $merged
}

function Get-ProcessStatusMarker {
    param([string]$Status)

    switch ($Status) {
        'Succeeded' { return @{ Glyph = [char]0x2713; Color = 'Green' } }   # ✓
        'Failed' { return @{ Glyph = [char]0x2717; Color = 'Red' } }       # ✗
        'Running' { return @{ Glyph = [char]0x25CF; Color = 'Yellow' } }   # ●
        'Skipped' { return @{ Glyph = [char]0x2013; Color = 'DarkCyan' } } # –
        default { return @{ Glyph = [char]0x25CB; Color = 'DarkGray' } }   # ○
    }
}

function Write-ProcessStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessKey,
        [Parameter(Mandatory = $true)]
        [string[]]$StepNames,
        [Parameter(Mandatory = $true)]
        $State,
        [string]$Description
    )

    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host $ProcessKey -NoNewline -ForegroundColor Green
    if ($Description) {
        Write-Host "  $Description" -ForegroundColor White
    }
    else {
        Write-Host ""
    }

    $count = $StepNames.Count
    for ($i = 0; $i -lt $count; $i++) {
        $name = $StepNames[$i]
        $isLast = ($i -eq $count - 1)
        $branch = if ($isLast) { "$([char]0x2514)$([char]0x2500) " } else { "$([char]0x251C)$([char]0x2500) " }  # └── / ├──
        $pad = if ($isLast) { '    ' } else { "$([char]0x2502)   " }  # │

        $stepState = $State.steps[$name]
        $status = if ($stepState) { [string]$stepState.status } else { 'Pending' }
        $marker = Get-ProcessStatusMarker $status

        Write-Host "    " -NoNewline
        Write-Host $branch -NoNewline -ForegroundColor DarkGray
        Write-Host "$($marker.Glyph) " -NoNewline -ForegroundColor $marker.Color
        Write-Host $name -ForegroundColor White

        if ($status -eq 'Failed' -and $stepState.error) {
            Write-Host "    " -NoNewline
            Write-Host $pad -NoNewline -ForegroundColor DarkGray
            Write-Host $stepState.error -ForegroundColor DarkRed
        }
    }
    Write-Host ""
}
