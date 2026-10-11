#requires -version 7.0

# Process metadata for process=qrun. qbuild delegates via '& qrun -map <file> …'
# (see docs/plans/process-cli-contract.md). Members below remain as optional
# in-process fallbacks when a map file path is unavailable.

@{
    name        = 'qrun'
    description = 'Multi-step process runner (qrun CLI)'

    Invoke      = {
        param($Context)

        $mapPath = $null
        try {
            $mapPath = Resolve-ConfigMapProcessMapPath -Map $Context.Map -MapPath $Context.MapPath
        }
        catch {
            # Legacy in-memory handoff (tests / older callers)
            $invokeParams = @{
                entry = $Context.Entry
                map   = $Context.Map
            }
            if ($Context.Follow) { $invokeParams.Follow = $true }
            if ($Context.Force) { $invokeParams.Force = $true }
            if ($Context.Status) { $invokeParams.Status = $true }
            if ($Context.Reset) { $invokeParams.Reset = $true }

            $remaining = @($Context.RemainingArguments | Where-Object { $null -ne $_ })
            $extraBound = @{}
            if ($Context.Bound -is [hashtable] -or $Context.Bound -is [System.Collections.IDictionary]) {
                foreach ($key in @($Context.Bound.Keys)) {
                    if ($key -in @('entry', 'command', 'map', 'RemainingArguments', 'Follow', 'Force', 'Status', 'Reset')) {
                        continue
                    }
                    if ($key -like '_*') { continue }
                    $extraBound[$key] = $Context.Bound[$key]
                }
            }

            return Invoke-QRun @invokeParams @extraBound -RemainingArguments $remaining
        }

        $bound = @{}
        if ($Context.Bound -is [hashtable] -or $Context.Bound -is [System.Collections.IDictionary]) {
            foreach ($key in @($Context.Bound.Keys)) {
                $bound[$key] = $Context.Bound[$key]
            }
        }
        foreach ($flag in @('Follow', 'Force', 'Status', 'Reset')) {
            if ($Context.$flag -and -not $bound.ContainsKey($flag)) {
                $bound[$flag] = [switch]$true
            }
        }

        $splat = ConvertTo-ConfigMapProcessSplat `
            -MapPath $mapPath `
            -Entry $Context.Entry `
            -BoundParameters $bound `
            -RemainingArguments $Context.RemainingArguments

        Invoke-ConfigMapProcessCli -ProcessName 'qrun' -Splat $splat | Out-Null
    }

    GetDynamicParam = {
        param($Context)

        $follow = [bool]$Context.Follow
        try {
            $mapPath = Resolve-ConfigMapProcessMapPath -Map $Context.Map -MapPath $Context.MapPath
            return New-ConfigMapProcessDynamicParam `
                -ProcessName 'qrun' `
                -MapPath $mapPath `
                -Map $Context.Map `
                -Entry $Context.Entry `
                -Follow:$follow
        }
        catch {
            return Get-ProcessDynamicParam -Map $Context.Map -ProcessKey $Context.Entry -Follow:$follow
        }
    }

    WriteListEntry = {
        param($Context)

        $processEntry = $Context.EntryValue
        if ($processEntry -isnot [System.Collections.IDictionary]) {
            return @{ Handled = $false }
        }

        $stepNames = @(Get-ProcessStepNames $processEntry)
        if ($stepNames.Count -eq 0) {
            return @{ Handled = $false }
        }

        try {
            $mapPath = Resolve-ConfigMapProcessMapPath -Map $Context.Map -MapPath $Context.MapPath
            $splat = ConvertTo-ConfigMapProcessSplat -MapPath $mapPath -Entry 'list' -RemainingArguments @($Context.EntryKey)
            Invoke-ConfigMapProcessCli -ProcessName 'qrun' -Splat $splat | Out-Null
            return @{ Handled = $true }
        }
        catch {
            # fall through to in-process status
        }

        $baseDir = if ($processEntry._baseDir) {
            $processEntry._baseDir
        }
        elseif ($Context.Map._baseDir) {
            $Context.Map._baseDir
        }
        else {
            (Get-Location).Path
        }
        $sourceFile = if ($Context.Map._sourceFile) { [string]$Context.Map._sourceFile } else { $null }
        $statePath = Get-ProcessStatePath -ProcessKey $Context.EntryKey -BaseDir $baseDir -MapFile $sourceFile
        $state = Read-ProcessState -StatePath $statePath -ProcessKey $Context.EntryKey -StepNames $stepNames -MapFile $sourceFile

        $description = ''
        if ($processEntry.description) {
            $description = [string]$processEntry.description
        }

        Write-ProcessStatus `
            -ProcessKey $Context.EntryKey `
            -StepNames $stepNames `
            -State $state `
            -Description $description

        return @{ Handled = $true }
    }

    InvokeStateCommand = {
        param($Context)

        $action = if ($Context.StateAction) { [string]$Context.StateAction } else { 'show' }
        $processKey = $Context.StateProcessKey
        $baseDir = if ($Context.Map._baseDir) { $Context.Map._baseDir } else { (Get-Location).Path }
        $sourceFile = if ($Context.Map._sourceFile) { [string]$Context.Map._sourceFile } else { $null }
        $operationContext = if ($Context.OperationContext) {
            $Context.OperationContext
        }
        else {
            New-ConfigMapOperationContext
        }

        Invoke-ProcessStateCommand `
            -Action $action `
            -ProcessKey $processKey `
            -Map $Context.Map `
            -BaseDir $baseDir `
            -MapFile $sourceFile `
            -OperationContext $operationContext `
            -Title 'QBUILD' `
            -ProcessName 'qrun'

        return @{ Handled = $true }
    }
}
