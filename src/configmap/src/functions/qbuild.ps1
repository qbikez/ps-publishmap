function Invoke-QBuild {
    [CmdletBinding()]
    param(
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    $mapPath = if ($fakeBoundParameters.map) { $fakeBoundParameters.map } else { "./.build.map.ps1" }
                    $localMapExists = Test-Path $mapPath

                    $userMap = try {
                        Import-ConfigMap -Map $fakeBoundParameters.map -Fallback "./.build.map.ps1" -ErrorAction Stop
                    }
                    catch {
                        if ($_.Exception.Message -match '^map file .* not found$|^No map provided and fallback .* not found$|^map is null and defaultMapFile is not provided$') {
                            $null
                        }
                        else {
                            throw
                        }
                    }
                    if ($userMap) {
                        $userMap = $userMap | Assert-ConfigMap
                    }

                    $completions = [System.Collections.Generic.List[string]]::new()
                    if ($userMap) {
                        foreach ($c in @(Get-EntryCompletion $userMap -language "build" @PSBoundParameters)) {
                            if ($c) { $completions.Add([string]$c) | Out-Null }
                        }
                    }

                    $qbuildModule = (Get-Command Invoke-QBuild).Module
                    $internalCommands = & $qbuildModule { Get-ConfigMapInternalCommands -Language build }
                    foreach ($item in $internalCommands.GetEnumerator()) {
                        if (-not ([string]$item.Key).StartsWith($wordToComplete)) {
                            continue
                        }
                        $includeCompletion = & $qbuildModule {
                            param($commandEntry, $mapExists)
                            Test-ConfigMapCommandCompletion -Entry $commandEntry -LocalMapExists $mapExists
                        } $item.Value $localMapExists
                        if (-not $includeCompletion) {
                            continue
                        }
                        if (-not $completions.Contains([string]$item.Key)) {
                            $completions.Add([string]$item.Key) | Out-Null
                        }
                    }

                    try {
                        $resolvedMapPath = Resolve-MapPath -Map $userMap
                        if ($resolvedMapPath) {
                            foreach ($procName in @(Get-ConfigMapProcessNamesInMap -Map $userMap)) {
                                $procWords = Get-ConfigMapProcessCompleteWord `
                                    -ProcessName $procName `
                                    -MapPath $resolvedMapPath `
                                    -Word $wordToComplete
                                if ($null -eq $procWords) { continue }
                                foreach ($w in @($procWords)) {
                                    if ($w -and -not $completions.Contains([string]$w)) {
                                        $completions.Add([string]$w) | Out-Null
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        # No file path / process discovery failure → keep map-only completions
                    }

                    return @($completions)
                }
                catch {
                    return "ERROR [-entry]: $($_.Exception.Message) $($_.ScriptStackTrace)"
                }
            })]
        [Parameter(Position = 0)]
        $entry = $null,

        [Parameter(DontShow)]
        $command = "exec",
        [Parameter(DontShow)]
        $map = "./.build.map.ps1",

        [Parameter(Position = 1, DontShow)]
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    $module = Get-Module ConfigMap | Select-Object -First 1
                    if (-not $module) { return @() }
                    return & $module {
                        param($Ast, $Bound, $Word)
                        Get-QBuildProcessArgumentCompletion `
                            -CommandAst $Ast `
                            -FakeBoundParameters $Bound `
                            -Word $Word `
                            -Position Action
                    } $commandAst $fakeBoundParameters $wordToComplete
                }
                catch {
                    return @()
                }
            })]
        [string]$ProcessAction,

        [Parameter(Position = 2, DontShow)]
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    $module = Get-Module ConfigMap | Select-Object -First 1
                    if (-not $module) { return @() }
                    return & $module {
                        param($Ast, $Bound, $Word)
                        Get-QBuildProcessArgumentCompletion `
                            -CommandAst $Ast `
                            -FakeBoundParameters $Bound `
                            -Word $Word `
                            -Position Value
                    } $commandAst $fakeBoundParameters $wordToComplete
                }
                catch {
                    return @()
                }
            })]
        [string]$ProcessValue,

        [Parameter(ValueFromRemainingArguments = $true, DontShow = $true)]
        [string[]]$RemainingArguments
    )
    dynamicparam {
        if (-not $entry) {
            return
        }
        try {
            $dynUserMap = try {
                . $ImportConfigMap -Map $map -Fallback "./.build.map.ps1" | Assert-ConfigMap
            }
            catch {
                if ($_.Exception.Message -match '^map file .* not found$|^No map provided and fallback .* not found$|^map is null and defaultMapFile is not provided$') {
                    $null
                }
                else {
                    throw
                }
            }
            $dynMap = Merge-ConfigMapCommands -Map $dynUserMap -Language build

            if (Test-ConfigMapInternalCommand -Name $entry -Language build) {
                return Get-EntryDynamicParam $dynMap $entry $command -skip 0 -bound $PSBoundParameters
            }
            if (!$dynUserMap) {
                return
            }

            $settings = Get-ConfigMapSettingsForPath -Map $dynMap -Path $entry
            if ($settings.Process -ne 'qbuild') {
                $mapPath = Resolve-MapPath -Map $dynMap
                $followHint = [bool]$PSBoundParameters['Follow']
                if (-not $mapPath) {
                    return Get-ProcessDynamicParam -Map $dynMap -ProcessKey $entry -Follow:$followHint
                }
                return New-ConfigMapProcessDynamicParam `
                    -ProcessName $settings.Process `
                    -MapPath $mapPath `
                    -Map $dynMap `
                    -Entry $entry `
                    -Follow:$followHint
            }
            $result = Get-EntryDynamicParam $dynMap $entry $command -skip 0 -bound $PSBoundParameters
            Write-Debug "Dynamic parameters for entry '$entry': $($result.Keys -join ', ')"
            return $result
        }
        catch {
            return "ERROR [dynamic]: $($_.Exception.Message) $($_.ScriptStackTrace)"
        }
    }

    process {
        $mapPath = $map
        $userMap = try {
            . $ImportConfigMap -Map $map -Fallback "./.build.map.ps1" | Assert-ConfigMap
        }
        catch {
            if ($_.Exception.Message -match '^map file .* not found$|^No map provided and fallback .* not found$|^map is null and defaultMapFile is not provided$') {
                $null
            }
            else {
                throw
            }
        }
        $map = Merge-ConfigMapCommands -Map $userMap -Language build

        if (-not $entry) {
            $entry = 'list'
        }

        $isInternalCommand = Test-ConfigMapInternalCommand -Name $entry -Language build
        if (!$userMap -and !$isInternalCommand) {
            Write-Help -invocation $MyInvocation -mapPath "./.build.map.ps1"
            return
        }

        $operationContext = New-ConfigMapOperationContext
        if (!$isInternalCommand) {
            $processSettings = Get-ConfigMapSettingsForPath -Map $map -Path $entry -OperationContext $operationContext

            if ($processSettings.Process -ne 'qbuild') {
                $resolvedMapPath = Resolve-MapPath -Map $map
                if (-not $resolvedMapPath) {
                    throw "Cannot delegate process '$($processSettings.Process)' for entry '$entry': the map has no _sourceFile."
                }
                $processArguments = @(
                    $ProcessAction
                    $ProcessValue
                    $RemainingArguments
                ) | Where-Object { $null -ne $_ -and "$_" -ne '' }
                $splat = ConvertTo-ConfigMapProcessSplat `
                    -MapPath $resolvedMapPath `
                    -Entry $entry `
                    -BoundParameters $PSBoundParameters `
                    -RemainingArguments $processArguments

                Invoke-ConfigMapProcessCli -ProcessName $processSettings.Process -Splat $splat
                return
            }
        }

        $targets = Get-MapEntries $map $entry -language "build" -OperationContext $operationContext
        
        # Validate that the entry exists
        if (!$targets -or $targets.Count -eq 0) {
            throw "Entry '$entry' not found. Run 'qbuild list' to see all available commands."
        }
        
        Write-Verbose "running targets: $($targets.Key)"

        $bound = @{}
        foreach ($item in $PSBoundParameters.GetEnumerator()) {
            if ($item.Key -notin @('entry', 'ProcessAction', 'ProcessValue', 'RemainingArguments')) {
                $bound[$item.Key] = $item.Value
            }
        }
        $passthrough = @($ProcessAction, $ProcessValue, $RemainingArguments) | Where-Object { $null -ne $_ }
        if ($isInternalCommand) {
            $bound._context = @{
                Map                = $map
                UserMap            = $userMap
                MapArgument        = $mapPath
                Invocation         = $MyInvocation
                RemainingArguments = @($passthrough)
            }
        }
        elseif ($passthrough.Count -gt 0) {
            $bound._context = @{}
            $bound._context['additionalArgs'] = @($passthrough)
        }

        $hookContext = @{
            MainCommand        = 'qbuild'
            Entry              = $entry
            Targets            = @($targets)
            Map                = $map
            MapPath            = $mapPath
            Command            = $command
            Bound              = $bound
            RemainingArguments = $passthrough
        }

        $hookEntryKey = if ($entry -match '^(.*)\.all$') { $Matches[1] } else { [string]$entry }
        $hookEntry = $map
        if ($hookEntryKey) {
            $resolvedHookEntry = Get-MapEntry $map $hookEntryKey -language "build" -OperationContext $operationContext
            if ($null -ne $resolvedHookEntry) {
                $hookEntry = $resolvedHookEntry
            }
        }

        $hookResult = Invoke-WithEntrySettings -Map $map -EntryKey $hookEntryKey -Entry $hookEntry -OperationContext $operationContext -ScriptBlock {
            Invoke-ConfigMapPluginHooks -HookName 'InvokeQBuildTargets' -Context $hookContext
        }
        if ($hookResult.Handled) {
            return $hookResult.Result
        }

        foreach ($_ in $targets) {
            $targetKey = $_.key
            $targetEntry = $_.value
            Write-Verbose "running entry '$targetKey'"

            if ($command -eq "exec" `
                    -and $targetEntry -is [System.Collections.IDictionary] `
                    -and -not (Get-EntryHasExec $targetEntry) `
                    -and (Test-IsParentEntry $targetEntry)) {
                Write-ChooseSubcommand -parentKey $targetKey -parentEntry $targetEntry -invocation $MyInvocation -language "build"
                return
            }

            Invoke-WithEntrySettings -Map $map -EntryKey $targetKey -Entry $targetEntry -OperationContext $operationContext -ScriptBlock {
                Invoke-EntryWrapper -MainCommand 'qbuild' -TargetKey $targetKey -TargetEntry $targetEntry -Command $command -Bound $bound -RemainingArguments $passthrough
            }
        }

    }
}

Set-Alias -Name "qbuild" -Value "Invoke-QBuild" -Force
