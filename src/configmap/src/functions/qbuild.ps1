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
                        return @("!init", "!settings", "!describe", "!agent.init", "!state", "help", "list") | ? { $_.startswith($wordToComplete) }
                    }
                    $map = $map | Assert-ConfigMap

                    $completions = Get-EntryCompletion $map -language "build" @PSBoundParameters
                    # Include !init if no local map file exists
                    if (!$localMapExists) {
                        $completions = @("!init" | ? { $_.startswith($wordToComplete) }) + $completions
                    }
                    return @(@("!settings", "!describe", "!agent.init", "!state", "help", "list") | ? { $_.startswith($wordToComplete) }) + $completions
                }
                catch {
                    return "ERROR [-entry]: $($_.Exception.Message) $($_.ScriptStackTrace)"
                }
            })]
        [Parameter(Position = 0)]
        $entry = $null,

        [switch]$Follow,
        [switch]$Force,
        [switch]$Status,
        [switch]$Reset,

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
        if (-not $entry -or $entry -in @('help', 'list', '!init', '!settings', '!describe', '!state', '!agent.init')) {
            return
        }
        try {
            $dynMap = . $ImportConfigMap -Map $map -Fallback "./.build.map.ps1" | Assert-ConfigMap
            $root = Resolve-ConfigMapProcessRoot -Map $dynMap -Entry $entry
            if ($root.Process -ne 'qbuild') {
                $dynResult = Invoke-ConfigMapProcess -ProcessName $root.Process -Member 'GetDynamicParam' -Context @{
                    Map    = $dynMap
                    Entry  = $entry
                    Follow = [bool]$PSBoundParameters['Follow']
                }
                if ($dynResult -is [System.Management.Automation.RuntimeDefinedParameterDictionary]) {
                    return $dynResult
                }
                if ($dynResult.Result -is [System.Management.Automation.RuntimeDefinedParameterDictionary]) {
                    return $dynResult.Result
                }
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
            Write-Host "qbuild <process> [-Follow] [-Force] [-Status] [-Reset]  # when process=qrun"
            Write-Host "qbuild !state [show|clean] [<process>]"
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
        if ($entry -eq "!state") {
            $stateMap = . $ImportConfigMap -Map $map -Fallback "./.build.map.ps1" -ErrorAction Ignore
            if (!$stateMap) {
                Write-Help -invocation $MyInvocation -mapPath "./.build.map.ps1"
                return
            }

            $stateArgs = @($RemainingArguments | Where-Object { $_ })
            $action = 'show'
            $processFilter = $null
            if ($stateArgs.Count -ge 1) {
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
                    throw "!state expects 'show' or 'clean', got '$($stateArgs[0])'. Try: qbuild !state show"
                }
            }

            $operationContext = New-ConfigMapOperationContext
            $stateResult = Invoke-ConfigMapProcess -ProcessName 'qrun' -Member 'InvokeStateCommand' -Context @{
                Map              = $stateMap
                MapPath          = $map
                StateAction      = $action
                StateProcessKey  = $processFilter
                OperationContext = $operationContext
                MainCommand      = 'qbuild'
            }
            return $stateResult.Result
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

            $bound = @{}
            foreach ($key in $PSBoundParameters.Keys) {
                if ($key -in @('entry', 'command', 'map', 'RemainingArguments', 'Follow', 'Force', 'Status', 'Reset')) {
                    continue
                }
                $bound[$key] = $PSBoundParameters[$key]
            }
            $passthrough = @($RemainingArguments) | Where-Object { $null -ne $_ }

            $forwardResult = Invoke-ConfigMapProcess -ProcessName $processRoot.Process -Member 'Invoke' -Context @{
                MainCommand        = 'qbuild'
                Map                = $map
                MapPath            = $mapPath
                Entry              = $entry
                EntryKey           = $processRoot.EntryKey
                EntryValue         = $processRoot.EntryValue
                Bound              = $bound
                RemainingArguments = $passthrough
                OperationContext   = $operationContext
                Follow             = [bool]$Follow
                Force              = [bool]$Force
                Status             = [bool]$Status
                Reset              = [bool]$Reset
            }
            return $forwardResult.Result
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
        $bound.Remove("Follow") | Out-Null
        $bound.Remove("Force") | Out-Null
        $bound.Remove("Status") | Out-Null
        $bound.Remove("Reset") | Out-Null
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
