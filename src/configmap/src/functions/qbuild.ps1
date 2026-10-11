function Invoke-QBuild {
    [CmdletBinding()]
    param(
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    $mapPath = if ($fakeBoundParameters.map) { $fakeBoundParameters.map } else { "./.build.map.ps1" }
                    $localMapExists = Test-Path $mapPath

                    $mapNotFound = $false
                    $map = try {
                        Import-ConfigMap -Map $fakeBoundParameters.map -Fallback "./.build.map.ps1" -ErrorAction Stop
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
                        return @("!init", "!settings", "!describe", "!agent.init", "help", "list") | ? { $_.startswith($wordToComplete) }
                    }
                    $map = $map | Assert-ConfigMap

                    $builtins = @(@("!settings", "!describe", "!agent.init", "help", "list") | ? { $_.startswith($wordToComplete) })
                    # Map-only baseline; enrich with process !complete -word when available.
                    $completions = [System.Collections.Generic.List[string]]::new()
                    foreach ($c in @(Get-EntryCompletion $map -language "build" @PSBoundParameters)) {
                        if ($c) { $completions.Add([string]$c) | Out-Null }
                    }

                    try {
                        $resolvedMapPath = Resolve-ConfigMapProcessMapPath -Map $map
                        if ($resolvedMapPath) {
                            foreach ($procName in @(Get-ConfigMapProcessNamesInMap -Map $map)) {
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

                    $completionArray = @($completions)
                    # Include !init if no local map file exists
                    if (!$localMapExists) {
                        $completionArray = @("!init" | ? { $_.startswith($wordToComplete) }) + $completionArray
                    }
                    return $builtins + $completionArray
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
        [Parameter(ValueFromRemainingArguments = $true, DontShow = $true)]
        [string[]]$RemainingArguments
    )
    dynamicparam {
        if ($entry -eq '!agent.init') {
            return New-QBuildAgentInitDynamicParam
        }
        if (-not $entry -or $entry -in @('help', 'list', '!init', '!settings', '!describe', '!agent.init')) {
            return
        }
        try {
            $dynMap = . $ImportConfigMap -Map $map -Fallback "./.build.map.ps1" | Assert-ConfigMap
            $root = Resolve-ConfigMapProcessRoot -Map $dynMap -Entry $entry
            if ($root.Process -ne 'qbuild') {
                $mapPath = Resolve-ConfigMapProcessMapPath -Map $dynMap
                $followHint = [bool]$PSBoundParameters['Follow']
                if (-not $mapPath) {
                    return Get-ProcessDynamicParam -Map $dynMap -ProcessKey $entry -Follow:$followHint
                }
                return New-ConfigMapProcessDynamicParam `
                    -ProcessName $root.Process `
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
        if ($entry -eq "help") {
            Write-Host "QBUILD"
            Write-Host "A command line tool to manage build scripts"
            Write-Host ""
            Write-Host "Usage:"
            Write-Host "qbuild <your-script-name>"
            Write-Host "qbuild <process>[.<step>] [process options]  # when _settings.process=<name> (e.g. qrun)"
            return
        }
        if ($entry -eq "list") {
            $map = . $ImportConfigMap -Map $map -Fallback "./.build.map.ps1"
            if (!$map) {
                $invocation = $MyInvocation
                Write-Help -invocation $invocation -mapPath "./.build.map.ps1"
                return
            }
            Write-MapHelp -map $map -invocation $MyInvocation
            return
        }
        if ($entry -eq "!init") {
            # Only check current directory - create new map regardless of parent configs
            if (Test-Path $map) {
                throw "map file '$map' already exists"
            }
            Initialize-BuildMap -file $map
            return
        }
        if ($entry -eq '!agent.init') {
            $agentScope = if ($PSBoundParameters.ContainsKey('Scope') -and $PSBoundParameters['Scope']) {
                $PSBoundParameters['Scope']
            }
            else {
                'project'
            }
            $agentTarget = if ($PSBoundParameters.ContainsKey('Agent') -and $PSBoundParameters['Agent']) {
                $PSBoundParameters['Agent']
            }
            else {
                'cursor'
            }
            return Initialize-QBuildAgent -Scope $agentScope -Agent $agentTarget
        }
        if ($entry -eq "!settings") {
            $settingsPath = @($RemainingArguments | Where-Object { $_ })
            if ($settingsPath.Count -gt 1) {
                throw "!settings accepts at most one command path."
            }

            $settingsMap = . $ImportConfigMap -Map $map -Fallback "./.build.map.ps1" -ErrorAction Ignore
            if (!$settingsMap) {
                return Get-ConfigMapSettings
            }

            return Get-ConfigMapSettingsForPath -Map $settingsMap -Path $settingsPath[0]
        }
        if ($entry -eq "!describe") {
            $describePath = @($RemainingArguments | Where-Object { $_ })
            if ($describePath.Count -gt 1) {
                throw "!describe accepts at most one command path."
            }

            $describeMap = $null
            try {
                $describeMap = . $ImportConfigMap -Map $map -Fallback "./.build.map.ps1"
            }
            catch {
                if ($_.Exception.Message -match '^map file .* not found$|^No map provided and fallback .* not found$|^map is null and defaultMapFile is not provided$') {
                    throw "No build map file found. Run 'qbuild !init' to create one, or provide -map."
                }
                throw
            }

            if ($describePath.Count -eq 1) {
                return Get-ConfigMapCommandCatalog -Map $describeMap -Path $describePath[0] -Language build
            }

            return Get-ConfigMapCommandCatalog -Map $describeMap -Language build
        }

        $mapPath = $map
        $map = . $ImportConfigMap -Map $map -Fallback "./.build.map.ps1" -ErrorAction Ignore
        if (!$map) {
            $invocation = $MyInvocation
            $commandName = $invocation.Statement

            Write-Help -invocation $invocation -mapPath "./.build.map.ps1"
            return
        }

        # If no entry is provided, list all available scripts
        if (-not $entry) {
            Write-MapHelp -map $map -invocation $MyInvocation
            return
        }

        $operationContext = New-ConfigMapOperationContext
        $processRoot = Resolve-ConfigMapProcessRoot -Map $map -Entry $entry -OperationContext $operationContext

        if ($processRoot.Process -ne 'qbuild') {
            if ($null -eq $processRoot.EntryValue) {
                throw "Entry '$entry' not found. Run 'qbuild list' to see all available commands."
            }

            $resolvedMapPath = Resolve-ConfigMapProcessMapPath -Map $map
            if (-not $resolvedMapPath) {
                throw "Cannot delegate process '$($processRoot.Process)' for entry '$entry': the map has no _sourceFile."
            }
            $splat = ConvertTo-ConfigMapProcessSplat `
                -MapPath $resolvedMapPath `
                -Entry $entry `
                -BoundParameters $PSBoundParameters `
                -RemainingArguments $RemainingArguments

            Invoke-ConfigMapProcessCli -ProcessName $processRoot.Process -Splat $splat | Out-Null
            return
        }

        $targets = Get-MapEntries $map $entry -language "build" -OperationContext $operationContext
        
        # Validate that the entry exists
        if (!$targets -or $targets.Count -eq 0) {
            throw "Entry '$entry' not found. Run 'qbuild list' to see all available commands."
        }
        
        Write-Verbose "running targets: $($targets.Key)"

        # FIXME: we already have the entry in $_.value, we know ITs own key, but we don't want to search for this key inside this object
        # we should pass null instead?
        #Invoke-EntryCommand -entry $_.value -key $_.Key $bound
        $bound = $PSBoundParameters
        $bound.Remove("entry") | Out-Null
        $bound.Remove("RemainingArguments") | Out-Null
        $passthrough = @($RemainingArguments) | Where-Object { $null -ne $_ }
        if ($passthrough.Count -gt 0) {
            if (-not $bound._context -or $bound._context -isnot [hashtable]) {
                $bound._context = @{}
            }
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
