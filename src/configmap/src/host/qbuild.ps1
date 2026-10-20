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

                    $completionPrefix = ""
                    $completionWord = $wordToComplete
                    $selectedEntries = @()
                    $lastComma = $wordToComplete.LastIndexOf(',')
                    if ($lastComma -ge 0) {
                        $completionPrefix = $wordToComplete.Substring(0, $lastComma + 1)
                        $completionWord = $wordToComplete.Substring($lastComma + 1)
                        $selectedEntries = $wordToComplete.Substring(0, $lastComma) -split ','
                    }

                    $entryCompParams = @{}
                    foreach ($k in $PSBoundParameters.Keys) { $entryCompParams[$k] = $PSBoundParameters[$k] }
                    $entryCompParams['wordToComplete'] = $completionWord

                    $completions = [System.Collections.Generic.List[string]]::new()
                    if ($userMap) {
                        foreach ($c in @(Get-EntryCompletion $userMap -language "build" @entryCompParams)) {
                            if ($c) { $completions.Add([string]$c) | Out-Null }
                        }
                    }

                    $configMapModule = (Get-Command Invoke-QBuild).Module
                    $internalCommands = & $configMapModule { Get-ConfigMapInternalCommands -Language build }
                    foreach ($item in $internalCommands.GetEnumerator()) {
                        if (-not ([string]$item.Key).StartsWith($completionWord)) {
                            continue
                        }
                        $includeCompletion = & $configMapModule {
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

                    if ($userMap -and 'list.'.StartsWith($completionWord) -eq $false -and $completionWord.StartsWith('list.')) {
                        foreach ($t in @(& $configMapModule { param($m) Get-ConfigMapListTypes -Map $m } $userMap)) {
                            if ("list.$t".StartsWith($completionWord)) { $completions.Add("list.$t") | Out-Null }
                        }
                    }

                    try {
                        $resolvedMapPath = Resolve-MapPath -Map $userMap
                        if ($resolvedMapPath) {
                            foreach ($procName in @(Get-ConfigMapProcessNamesInMap -Map $userMap)) {
                                $procWords = Get-ConfigMapProcessCompleteWord `
                                    -ProcessName (Get-ConfigMapProcessCliName -ProcessName $procName) `
                                    -MapPath $resolvedMapPath `
                                    -Word $completionWord
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

                    if ($completionPrefix) {
                        $result = $completions | Where-Object { $_ -notin $selectedEntries } | ForEach-Object { "$completionPrefix$_" }
                        return @($result)
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

        # Not positional. With dynamic parameters present, PowerShell binds these
        # slots out of order and treats the unbound strings as empty arguments.
        [Parameter(DontShow)]
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

        [Parameter(DontShow)]
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
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    $module = Get-Module ConfigMap | Select-Object -First 1
                    if (-not $module) { return @() }
                    return & $module {
                        param($Ast, $Bound, $Word)
                        $position = Get-QBuildRemainingArgumentPosition `
                            -CommandAst $Ast `
                            -FakeBoundParameters $Bound `
                            -Word $Word
                        if (-not $position) { return @() }
                        Get-QBuildProcessArgumentCompletion `
                            -CommandAst $Ast `
                            -FakeBoundParameters $Bound `
                            -Word $Word `
                            -Position $position
                    } $commandAst $fakeBoundParameters $wordToComplete
                }
                catch {
                    return @()
                }
            })]
        [string[]]$RemainingArguments
    )
    dynamicparam {
        if ($entry -is [array]) { return }
        # `list.<type>` shorthand resolves to the internal `list` command
        $dynEntry = if ($entry -match '^list\.(.+)$') { 'list' } else { $entry }
        if (-not $dynEntry) {
            # Host-only switch so entry scriptblocks may still declare their own -Version.
            # No -v alias: PowerShell binds -v to common -Verbose.
            $dict = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
            $attr = [System.Management.Automation.ParameterAttribute]::new()
            $param = [System.Management.Automation.RuntimeDefinedParameter]::new(
                'Version',
                [switch],
                [System.Attribute[]]@($attr)
            )
            $dict.Add('Version', $param)
            return $dict
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

            if (Test-ConfigMapInternalCommand -Name $dynEntry -Language build) {
                $internalParams = Get-EntryDynamicParam $dynMap $dynEntry $command -skip 0 -bound $PSBoundParameters
                if ($dynEntry -eq 'list' -and $internalParams.ContainsKey('Type')) {
                    $listTypes = Get-ConfigMapListTypes -Map $dynUserMap
                    $internalParams['Type'].Attributes.Add(
                        [System.Management.Automation.ArgumentCompleterAttribute]::new(
                            { param($c, $p, $word) $listTypes | Where-Object { $_ -like "$word*" } }.GetNewClosure()
                        )
                    )
                }
                return $internalParams
            }
            if (!$dynUserMap) {
                return
            }

            $settings = Get-ConfigMapSettingsForPath -Map $dynMap -Path $dynEntry
            $handler = Get-ConfigMapProcessHandler -Name $settings.Process
            if ($null -ne $handler) {
                if ($null -ne $handler.GetDynamicParam) {
                    $context = New-ConfigMapProcessContext `
                        -Map $dynMap `
                        -UserMap $dynUserMap `
                        -MapArgument $map `
                        -Entry $dynEntry `
                        -Command $command `
                        -Invocation $MyInvocation `
                        -BoundParameters $PSBoundParameters `
                        -ProcessAction $ProcessAction `
                        -ProcessValue $ProcessValue `
                        -RemainingArguments $RemainingArguments
                    return & $handler.GetDynamicParam $context
                }
                return Get-EntryDynamicParam $dynMap $dynEntry $command -skip 0 -bound $PSBoundParameters
            }
            if (Test-ConfigMapProcessCannotDelegate -ProcessName $settings.Process) {
                return Get-EntryDynamicParam $dynMap $dynEntry $command -skip 0 -bound $PSBoundParameters
            }

            $mapPath = Resolve-MapPath -Map $dynMap
            $followHint = [bool]$PSBoundParameters['Follow']
            if (-not $mapPath) {
                return Get-ProcessDynamicParam -Map $dynMap -ProcessKey $dynEntry -Follow:$followHint
            }
            return New-ConfigMapProcessDynamicParam `
                -ProcessName (Get-ConfigMapProcessCliName -ProcessName $settings.Process) `
                -MapPath $mapPath `
                -Map $dynMap `
                -Entry $dynEntry `
                -Follow:$followHint `
                -ProcessAction $ProcessAction `
                -ProcessValue $ProcessValue `
                -RemainingArguments $RemainingArguments
        }
        catch {
            return "ERROR [dynamic]: $($_.Exception.Message) $($_.ScriptStackTrace)"
        }
    }

    process {
        if ($entry -is [array]) {
            foreach ($e in $entry) {
                $params = @{}
                foreach ($k in $PSBoundParameters.Keys) { $params[$k] = $PSBoundParameters[$k] }
                $params['entry'] = $e
                Invoke-QBuild @params
            }
            return
        }

        if (-not $entry -and $PSBoundParameters['Version']) {
            $commandName = if ($MyInvocation.InvocationName) { $MyInvocation.InvocationName } else { 'qbuild' }
            return "$commandName $(Get-ConfigMapModuleVersion)"
        }

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

        # Shorthand: `list.<type>` == `list -Type <type>`
        if ($entry -match '^list\.(.+)$' -and -not $PSBoundParameters.ContainsKey('Type')) {
            $PSBoundParameters['Type'] = $Matches[1]
            $entry = 'list'
        }

        $isInternalCommand = Test-ConfigMapInternalCommand -Name $entry -Language build
        if (!$userMap -and !$isInternalCommand) {
            Write-Help -invocation $MyInvocation -mapPath "./.build.map.ps1"
            return
        }

        $operationContext = New-ConfigMapOperationContext
        $context = New-ConfigMapProcessContext `
            -Map $map `
            -UserMap $userMap `
            -MapArgument $mapPath `
            -Entry $entry `
            -Command $command `
            -Invocation $MyInvocation `
            -OperationContext $operationContext `
            -BoundParameters $PSBoundParameters `
            -ProcessAction $ProcessAction `
            -ProcessValue $ProcessValue `
            -RemainingArguments $RemainingArguments

        if (-not $isInternalCommand) {
            $processSettings = Get-ConfigMapSettingsForPath -Map $map -Path $entry -OperationContext $operationContext
            $handler = Get-ConfigMapProcessHandler -Name $processSettings.Process
            if ($null -ne $handler) {
                if ($null -eq $handler.Invoke) {
                    throw "Process handler '$($processSettings.Process)' has no Invoke implementation."
                }
                & $handler.Invoke $context
                return
            }

            Invoke-ConfigMapExternalProcess `
                -ProcessName $processSettings.Process `
                -Entry $entry `
                -Map $map `
                -BoundParameters $PSBoundParameters `
                -ProcessAction $ProcessAction `
                -ProcessValue $ProcessValue `
                -RemainingArguments $RemainingArguments
            return
        }

        Invoke-ConfigMapExecProcess -Context $context
    }
}

Set-Alias -Name "qbuild" -Value "Invoke-QBuild" -Force
