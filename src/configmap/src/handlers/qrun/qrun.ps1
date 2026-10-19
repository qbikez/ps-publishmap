. "$PSScriptRoot\process-state.ps1"

function Invoke-QRun {
    [CmdletBinding()]
    param(
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    $mapPath = if ($fakeBoundParameters.map) { $fakeBoundParameters.map } else { "./.process.map.ps1" }
                    $localMapExists = Test-Path $mapPath

                    $mapNotFound = $false
                    $map = try {
                        Import-ConfigMap -Map $fakeBoundParameters.map -Fallback "./.process.map.ps1" -ErrorAction Stop
                    }
                    catch {
                        if ($_.Exception.Message -match '^map file .* not found$|^No map provided and fallback .* not found$|^map is null and defaultMapFile is not provided$') {
                            $mapNotFound = $true
                            $null
                        }
                        else {
                            throw
                        }
                    }
                    if ($mapNotFound) {
                        return @("!init", "!state", "!complete", "help", "list") | ? { $_.startswith($wordToComplete) }
                    }
                    $map = $map | Assert-ConfigMap

                    $completions = Get-EntryCompletion $map -language "build" @PSBoundParameters
                    if (!$localMapExists) {
                        $completions = @("!init" | ? { $_.startswith($wordToComplete) }) + $completions
                    }
                    return @(@("!state", "!complete", "help", "list") | ? { $_.startswith($wordToComplete) }) + $completions
                }
                catch {
                    return "ERROR [-command]: $($_.Exception.Message) $($_.ScriptStackTrace)"
                }
            })]
        # Positional verb/path (list, help, !complete, bootstrap, …). Named -entry is separate
        # so `qrun !complete -params -entry bootstrap` does not double-bind.
        [Parameter(Position = 0)]
        $command = $null,

        # Process target for run (`qrun -entry bootstrap`) and !complete subject.
        [Parameter()]
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    $map = Import-ConfigMap -Map $fakeBoundParameters.map -Fallback "./.process.map.ps1" -ErrorAction Stop | Assert-ConfigMap
                    return @(Get-EntryCompletion $map -language "build" -wordToComplete $wordToComplete)
                }
                catch {
                    return @()
                }
            })]
        [string]$entry = $null,

        [switch]$Follow,
        [switch]$Force,
        [switch]$Status,
        [switch]$Reset,

        # Machine-readable !complete protocol (DontShow — used by qbuild / tooling)
        [Parameter(DontShow)]
        [string]$Word,
        [Parameter(DontShow)]
        [switch]$Params,

        [Parameter(DontShow)]
        $map = "./.process.map.ps1",

        [Parameter(ValueFromRemainingArguments = $true, DontShow = $true)]
        [string[]]$RemainingArguments
    )
    dynamicparam {
        $dynEntry = if ($entry) { $entry } elseif ($command -and $command -notin @('help', 'list', '!init', '!state', '!complete')) { $command } else { $null }
        if (-not $dynEntry) {
            return
        }
        try {
            $dynMap = . $ImportConfigMap -Map $map -Fallback "./.process.map.ps1" | Assert-ConfigMap
            return Get-ProcessDynamicParam -Map $dynMap -ProcessKey $dynEntry -Follow:$Follow
        }
        catch {
            return
        }
    }

    process {
        $qrunVerbs = @('help', 'list', '!init', '!state', '!complete')
        $verb = $null
        $processEntry = $null
        if ($command -in $qrunVerbs) {
            $verb = $command
        }
        elseif ($entry) {
            $processEntry = $entry
        }
        elseif ($command) {
            $processEntry = [string]$command
        }

        # Skip noise during tab-completion protocol calls.
        if ($verb -ne '!complete') {
            Write-ConfigMapDeprecatedProcessCliWarning -CliName 'qrun' -ProcessType 'steps'
        }

        if ($verb -eq "help") {
            Write-Host ""
            Write-Host "QRUN (deprecated)" -ForegroundColor Cyan
            Write-Host "Prefer qbuild with _settings.process = 'steps' in .build.map.ps1" -ForegroundColor Yellow
            Write-Host "Run multi-step processes with durable step state" -ForegroundColor Gray
            Write-Host ""
            Write-Host "USAGE:" -ForegroundColor Yellow
            Write-Host "    qrun <process> [-Force] [-Status] [-Reset]" -ForegroundColor White
            Write-Host "    qrun <process>.<step> [-Follow] [-Force]" -ForegroundColor White
            Write-Host "    qrun !state [show|clean] [<process>]" -ForegroundColor White
            Write-Host "    qrun list [<process>]" -ForegroundColor White
            Write-Host ""
            Write-Host "OPTIONS:" -ForegroundColor Yellow
            Write-Host "    -Follow           With a step path, also run all following steps" -ForegroundColor White
            Write-Host "    -Force            Rerun succeeded steps; also allow starting mid-process when prior steps are incomplete" -ForegroundColor White
            Write-Host "    -Status           Show persisted step statuses without running" -ForegroundColor White
            Write-Host "    -Reset            Clear persisted state for the process" -ForegroundColor White
            Write-Host ""
            Write-Host "STATE:" -ForegroundColor Yellow
            Write-Host "    qrun                      Show process state (same as !state)" -ForegroundColor White
            Write-Host "    qrun !state              Show all process state (alias for !state show)" -ForegroundColor White
            Write-Host "    qrun !state show [name]  Show state for all processes, or one process" -ForegroundColor White
            Write-Host "    qrun !state clean [name] Clean all process state, or one process" -ForegroundColor White
            Write-Host ""
            Write-Host "Dot paths work like qbuild: 'qrun bootstrap.prepare' runs that step; add -Follow to continue." -ForegroundColor Gray
            Write-Host ""
            return
        }

        if ($verb -eq "!complete") {
            $completeArgs = @{
                Mode  = $null
                Word  = $Word
                Entry = $entry
            }
            if ($Params) { $completeArgs.Mode = 'params' }
            elseif ($PSBoundParameters.ContainsKey('Word')) { $completeArgs.Mode = 'word' }

            $tokens = @($RemainingArguments | Where-Object { $null -ne $_ -and "$_" -ne '' })
            for ($i = 0; $i -lt $tokens.Count; $i++) {
                switch -Regex ($tokens[$i]) {
                    '^-params$' {
                        $completeArgs.Mode = 'params'
                    }
                    '^-word$' {
                        if ($i + 1 -lt $tokens.Count) {
                            $completeArgs.Word = $tokens[++$i]
                            if (-not $completeArgs.Mode) { $completeArgs.Mode = 'word' }
                        }
                    }
                    '^-entry$' {
                        if ($i + 1 -lt $tokens.Count) {
                            $completeArgs.Entry = $tokens[++$i]
                        }
                    }
                    default {
                        if (-not $completeArgs.Entry) {
                            $completeArgs.Entry = $tokens[$i]
                        }
                    }
                }
            }

            if (-not $completeArgs.Mode) {
                $global:LASTEXITCODE = 2
                return
            }

            $completeMap = . $ImportConfigMap -Map $map -Fallback "./.process.map.ps1" -ErrorAction Ignore
            if (!$completeMap) {
                $global:LASTEXITCODE = 2
                return
            }

            if ($completeArgs.Mode -eq 'params') {
                if (-not $completeArgs.Entry) {
                    $global:LASTEXITCODE = 2
                    return
                }

                $names = [System.Collections.Generic.List[string]]::new()
                foreach ($switchName in @('Follow', 'Force', 'Status', 'Reset')) {
                    $names.Add($switchName) | Out-Null
                }

                $followHint = $false
                $typed = Get-ProcessDynamicParam -Map $completeMap -ProcessKey $completeArgs.Entry -Follow:$followHint
                if ($typed) {
                    foreach ($key in @($typed.Keys)) {
                        if (-not $names.Contains($key)) {
                            $names.Add($key) | Out-Null
                        }
                    }
                }

                $names | ForEach-Object { $_ }
                $global:LASTEXITCODE = 0
                return
            }

            # -word: entry / token completion
            $prefix = if ($null -ne $completeArgs.Word) { [string]$completeArgs.Word } else { '' }
            $completions = @(Get-EntryCompletion -map $completeMap -language build -wordToComplete $prefix)
            $completions | ForEach-Object { $_ }
            $global:LASTEXITCODE = 0
            return
        }

        if ($verb -eq "list") {
            $listMap = . $ImportConfigMap -Map $map -Fallback "./.process.map.ps1"
            if (!$listMap) {
                Write-Help -invocation $MyInvocation -mapPath "./.process.map.ps1"
                return
            }

            $listEntry = @($RemainingArguments | Where-Object { $null -ne $_ -and "$_" -ne '' } | Select-Object -First 1)
            if ($listEntry.Count -eq 1) {
                $operationContext = New-ConfigMapOperationContext
                try {
                    $target = Resolve-ProcessTarget -Map $listMap -Entry $listEntry[0] -OperationContext $operationContext
                }
                catch {
                    throw "Entry '$($listEntry[0])' not found. Run 'qrun list' to see all available commands."
                }

                $processKey = $target.ProcessKey
                $listedEntry = $target.ProcessEntry
                $stepNames = @($target.StepNames)
                $baseDir = if ($listedEntry._baseDir) { $listedEntry._baseDir } elseif ($listMap._baseDir) { $listMap._baseDir } else { (Get-Location).Path }
                $sourceFile = if ($listMap._sourceFile) { [string]$listMap._sourceFile } else { $null }
                $statePath = Get-ProcessStatePath -ProcessKey $processKey -BaseDir $baseDir -MapFile $sourceFile
                $state = Read-ProcessState -StatePath $statePath -ProcessKey $processKey -StepNames $stepNames -MapFile $sourceFile
                $description = if ($listedEntry.description) { [string]$listedEntry.description } else { '' }

                Write-ProcessStatus `
                    -ProcessKey $processKey `
                    -StepNames $stepNames `
                    -State $state `
                    -Description $description `
                    -ProcessEntry $listedEntry
                return
            }

            Write-MapHelp -map $listMap -invocation $MyInvocation -language "build"
            return
        }

        if ($verb -eq "!init") {
            if (Test-Path $map) {
                throw "map file '$map' already exists"
            }
            Initialize-ProcessMap -file $map
            return
        }

        if (-not $processEntry -or $verb -eq "!state") {
            $stateArgs = @($RemainingArguments | Where-Object { $_ })
            $action = 'show'
            $processFilter = $null

            if ($verb -eq "!state" -and $stateArgs.Count -ge 1) {
                if ($stateArgs[0] -in @('show', 'clean')) {
                    $action = $stateArgs[0]
                    if ($stateArgs.Count -ge 2) {
                        $processFilter = $stateArgs[1]
                    }
                    if ($stateArgs.Count -gt 2) {
                        throw "!state $action accepts at most one process name."
                    }
                }
                else {
                    throw "!state expects 'show' or 'clean', got '$($stateArgs[0])'. Try: qrun !state show"
                }
            }

            $stateMap = . $ImportConfigMap -Map $map -Fallback "./.process.map.ps1" -ErrorAction Ignore
            if (!$stateMap) {
                Write-Help -invocation $MyInvocation -mapPath "./.process.map.ps1"
                return
            }

            $baseDir = if ($stateMap._baseDir) { $stateMap._baseDir } else { (Get-Location).Path }
            $sourceFile = if ($stateMap._sourceFile) { [string]$stateMap._sourceFile } else { $null }
            $operationContext = New-ConfigMapOperationContext

            Invoke-ProcessStateCommand `
                -Action $action `
                -ProcessKey $processFilter `
                -Map $stateMap `
                -BaseDir $baseDir `
                -MapFile $sourceFile `
                -OperationContext $operationContext
            return
        }

        $mapPath = $map
        $map = . $ImportConfigMap -Map $map -Fallback "./.process.map.ps1" -ErrorAction Ignore
        if (!$map) {
            Write-Help -invocation $MyInvocation -mapPath "./.process.map.ps1"
            return
        }

        $operationContext = New-ConfigMapOperationContext
        $target = Resolve-ProcessTarget -Map $map -Entry $processEntry -OperationContext $operationContext
        $processKey = $target.ProcessKey
        $processMapEntry = $target.ProcessEntry
        $stepNames = @($target.StepNames)
        $fromStep = $target.ImpliedStep

        if ($Follow -and -not $fromStep) {
            throw "-Follow requires a step path (e.g. qrun bootstrap.restore -Follow)"
        }

        $baseDir = if ($processMapEntry._baseDir) { $processMapEntry._baseDir } elseif ($map._baseDir) { $map._baseDir } else { (Get-Location).Path }
        $sourceFile = if ($map._sourceFile) { [string]$map._sourceFile } else { $null }
        $statePath = Get-ProcessStatePath -ProcessKey $processKey -BaseDir $baseDir -MapFile $sourceFile

        if ($Reset) {
            Reset-ProcessState -StatePath $statePath
            Write-Host "Reset process state for '$processKey'" -ForegroundColor Yellow
            if (-not $Status -and -not $fromStep -and -not $Follow -and -not $Force) {
                return
            }
        }

        $state = Read-ProcessState -StatePath $statePath -ProcessKey $processKey -StepNames $stepNames -MapFile $sourceFile

        if ($Status) {
            Write-ProcessStatus -ProcessKey $processKey -StepNames $stepNames -State $state -ProcessEntry $processMapEntry
            return
        }

        $skippedPrior = @()
        if ($fromStep) {
            $skippedPrior = @(Assert-ProcessPriorSteps -StepNames $stepNames -FromStep $fromStep -State $state -Force:$Force)
        }

        $stepsToConsider = Get-ProcessStepsToRun -StepNames $stepNames -FromStep $fromStep -Follow:$Follow
        $total = $stepNames.Count

        Write-Host ""
        Write-Host "PROCESS " -NoNewline -ForegroundColor Cyan
        Write-Host $processKey -ForegroundColor White
        if ($fromStep) {
            $rangeLabel = if ($Follow) { "$fromStep …" } else { $fromStep }
            Write-Host "Step: $rangeLabel" -ForegroundColor DarkGray
        }
        Write-Host "State: $statePath" -ForegroundColor DarkGray
        Write-Host ""

        foreach ($priorName in $skippedPrior) {
            $priorIndex = [array]::IndexOf($stepNames, $priorName) + 1
            $priorStatus = if ($state.steps[$priorName]) { [string]$state.steps[$priorName].status } else { 'Pending' }
            Write-Host "[$priorIndex/$total] " -NoNewline -ForegroundColor DarkGray
            Write-Host "SKIP" -NoNewline -ForegroundColor DarkYellow
            Write-Host "  $priorName" -NoNewline -ForegroundColor White
            Write-Host "  (forced; was $priorStatus)" -ForegroundColor DarkGray
        }

        $bound = @{}
        foreach ($key in $PSBoundParameters.Keys) {
            if ($key -in @('command', 'entry', 'Follow', 'Force', 'Status', 'Reset', 'map', 'RemainingArguments', 'Word', 'Params')) {
                continue
            }
            $bound[$key] = $PSBoundParameters[$key]
        }
        $passthrough = @($RemainingArguments) | Where-Object { $null -ne $_ }
        if ($passthrough.Count -gt 0) {
            $bound._context = @{ additionalArgs = @($passthrough) }
        }

        $ran = 0
        $skipped = 0

        foreach ($stepName in $stepsToConsider) {
            $stepIndex = [array]::IndexOf($stepNames, $stepName) + 1
            $prefix = "[$stepIndex/$total]"
            $stepStatus = if ($state.steps[$stepName]) { [string]$state.steps[$stepName].status } else { 'Pending' }

            if ($stepStatus -eq 'Succeeded' -and -not $Force) {
                Write-Host "$prefix " -NoNewline -ForegroundColor DarkGray
                Write-Host "SKIP" -NoNewline -ForegroundColor DarkCyan
                Write-Host "  $stepName" -NoNewline -ForegroundColor White
                Write-Host "  (already succeeded)" -ForegroundColor DarkGray
                $skipComments = @(Invoke-ProcessStepSkippedScript -ProcessEntry $processMapEntry -StepName $stepName)
                foreach ($line in $skipComments) {
                    Write-Host "           $line" -ForegroundColor DarkGray
                }
                $skipped++
                continue
            }

            Write-Host "$prefix " -NoNewline -ForegroundColor DarkGray
            Write-Host "RUN " -NoNewline -ForegroundColor Yellow
            Write-Host "  $stepName..." -ForegroundColor White

            $state.steps[$stepName] = [ordered]@{
                status     = 'Running'
                startedAt  = (Get-Date).ToString('o')
                finishedAt = $null
                error      = $null
            }
            Write-ProcessState -StatePath $statePath -State $state

            $stepEntry = Get-ProcessStepEntry -ProcessEntry $processMapEntry -StepName $stepName
            try {
                Push-Location $baseDir
                try {
                    $settingsEntry = if ($stepEntry -is [System.Collections.IDictionary]) { $stepEntry } else { $processMapEntry }
                    Invoke-WithEntrySettings -Map $map -EntryKey "$processKey.$stepName" -Entry $settingsEntry -OperationContext $operationContext -ScriptBlock {
                        Invoke-EntryCommand -entry $stepEntry -key "exec" -bound $bound
                    }
                }
                finally {
                    Pop-Location
                }

                $state.steps[$stepName] = [ordered]@{
                    status     = 'Succeeded'
                    startedAt  = $state.steps[$stepName].startedAt
                    finishedAt = (Get-Date).ToString('o')
                    error      = $null
                }
                Write-ProcessState -StatePath $statePath -State $state

                Write-Host "$prefix " -NoNewline -ForegroundColor DarkGray
                Write-Host "OK  " -NoNewline -ForegroundColor Green
                Write-Host "  $stepName" -ForegroundColor White
                $ran++
            }
            catch {
                $errMsg = $_.Exception.Message
                $state.steps[$stepName] = [ordered]@{
                    status     = 'Failed'
                    startedAt  = $state.steps[$stepName].startedAt
                    finishedAt = (Get-Date).ToString('o')
                    error      = $errMsg
                }
                Write-ProcessState -StatePath $statePath -State $state

                Write-Host "$prefix " -NoNewline -ForegroundColor DarkGray
                Write-Host "FAIL" -NoNewline -ForegroundColor Red
                Write-Host "  $stepName" -ForegroundColor White
                Write-Host "       $errMsg" -ForegroundColor DarkRed
                throw
            }
        }

        Write-Host ""
        Write-Host "Process '$processKey' finished" -NoNewline -ForegroundColor Green
        Write-Host "  (ran: $ran, skipped: $skipped)" -ForegroundColor DarkGray
        Write-Host ""
    }
}

Set-Alias -Name "qrun" -Value "Invoke-QRun" -Force

# Canonical process type for qbuild maps; CLI alias remains qrun.
Register-ConfigMapCliProcess -Name 'steps' -CliName 'qrun'
