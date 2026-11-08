function Get-QBuildHostParameterName {
    <#
    .SYNOPSIS
        Names of qbuild's own parameters, which must not be forwarded to entries or child command lines.

    .DESCRIPTION
        ProcessAction and ProcessValue are not included: they carry the entry's own
        arguments, and some callers forward them.
    #>
    [OutputType([string[]])]
    param()

    @('entry', 'command', 'map', 'RemainingArguments')
}

function Invoke-QBuild {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        $entry = $null,

        [Parameter(DontShow)]
        $command = "exec",
        [Parameter(DontShow)]
        $map = "./.build.map.ps1",

        # Not positional. With dynamic parameters present, PowerShell binds these
        # slots out of order and treats the unbound strings as empty arguments.
        [Parameter(DontShow)]
        [string]$ProcessAction,

        [Parameter(DontShow)]
        [string]$ProcessValue,

        [Parameter(ValueFromRemainingArguments = $true, DontShow = $true)]
        [string[]]$RemainingArguments
    )
    dynamicparam {
        if ($entry -is [array]) { return }
        if (-not $entry) {
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

            if (Test-ConfigMapInternalCommand -Name $entry -Language build) {
                return Get-EntryDynamicParam $dynMap $entry $command -skip 0 -bound $PSBoundParameters
            }
            if (!$dynUserMap) {
                return
            }

            # A local copy: assigning $entry here would leak into the process block.
            $entryPath = $entry
            $generatedEntry = Resolve-ConfigMapProcessGeneratedEntry -Map $dynMap -Path $entry
            if ($generatedEntry) {
                $entryPath = $generatedEntry.Entry
            }

            $settings = Get-ConfigMapSettingsForPath -Map $dynMap -Path $entryPath
            $handler = Get-ConfigMapProcessHandler -Name $settings.Process
            if ($null -ne $handler) {
                if ($null -ne $handler.GetDynamicParam) {
                    $context = New-ConfigMapProcessContext `
                        -Map $dynMap `
                        -UserMap $dynUserMap `
                        -MapArgument $map `
                        -Entry $entryPath `
                        -GeneratedEntry $generatedEntry.Name `
                        -Command $command `
                        -Invocation $MyInvocation `
                        -BoundParameters $PSBoundParameters `
                        -ProcessAction $ProcessAction `
                        -ProcessValue $ProcessValue `
                        -RemainingArguments $RemainingArguments
                    return & $handler.GetDynamicParam $context
                }
                return Get-EntryDynamicParam $dynMap $entry $command -skip 0 -bound $PSBoundParameters
            }
            if (Test-ConfigMapProcessCannotDelegate -ProcessName $settings.Process) {
                return Get-EntryDynamicParam $dynMap $entry $command -skip 0 -bound $PSBoundParameters
            }

            $mapPath = Resolve-MapPath -Map $dynMap
            $followHint = [bool]$PSBoundParameters['Follow']
            if (-not $mapPath) {
                return Get-ProcessDynamicParam -Map $dynMap -ProcessKey $entry -Follow:$followHint
            }
            return New-ConfigMapProcessDynamicParam `
                -ProcessName (Get-ConfigMapProcessCliName -ProcessName $settings.Process) `
                -MapPath $mapPath `
                -Map $dynMap `
                -Entry $entry `
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
                $global:LASTEXITCODE = 0
                Invoke-QBuild @params
                if ($global:LASTEXITCODE) {
                    throw "Entry '$e' failed with exit code $global:LASTEXITCODE. Stopping."
                }
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

        $isInternalCommand = Test-ConfigMapInternalCommand -Name $entry -Language build
        if (!$userMap -and !$isInternalCommand) {
            Write-Help -invocation $MyInvocation -mapPath "./.build.map.ps1"
            return
        }

        $operationContext = New-ConfigMapOperationContext
        $generatedEntry = if (-not $isInternalCommand) {
            Resolve-ConfigMapProcessGeneratedEntry -Map $map -Path $entry -OperationContext $operationContext
        }
        if ($generatedEntry) {
            $entry = $generatedEntry.Entry
        }
        $runContext = New-ConfigMapRunContext -Map $map -OperationContext $operationContext
        $context = New-ConfigMapProcessContext `
            -Map $map `
            -UserMap $userMap `
            -MapArgument $mapPath `
            -Entry $entry `
            -GeneratedEntry $generatedEntry.Name `
            -Command $command `
            -Invocation $MyInvocation `
            -OperationContext $operationContext `
            -RunContext $runContext `
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

function Get-QBuildEntryCompletion {
    <#
    .SYNOPSIS
        Completes the qbuild -entry argument: map entries, internal commands and external process words.
    .DESCRIPTION
        A comma-separated word ("clean,b") completes its last item and skips entries already listed.
    #>
    param(
        [AllowEmptyString()]
        [string]$WordToComplete = '',
        [hashtable]$FakeBoundParameters = @{}
    )

    try {
        $userMap = try {
            Import-ConfigMap -Map $FakeBoundParameters.map -Fallback "./.build.map.ps1" -ErrorAction Stop
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
        $completionWord = $WordToComplete
        $selectedEntries = @()
        $lastComma = $WordToComplete.LastIndexOf(',')
        if ($lastComma -ge 0) {
            $completionPrefix = $WordToComplete.Substring(0, $lastComma + 1)
            $completionWord = $WordToComplete.Substring($lastComma + 1)
            $selectedEntries = $WordToComplete.Substring(0, $lastComma) -split ','
        }

        $completions = [System.Collections.Generic.List[string]]::new()
        if ($userMap) {
            foreach ($c in @(Get-EntryCompletion $userMap -language "build" -wordToComplete $completionWord)) {
                if ($c) { $completions.Add([string]$c) | Out-Null }
            }

            $generatedEntry = Resolve-ConfigMapProcessGeneratedEntry -Map $userMap -Path $completionWord
            if ($generatedEntry) {
                $handler = Get-ConfigMapProcessHandler -Name $generatedEntry.Process
                try { $names = @((& $handler.GetEntries @{ Map = $userMap; Entry = $generatedEntry.Entry }).Keys) } catch { $names = @() }
                foreach ($name in $names) {
                    if ($name.StartsWith($generatedEntry.Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $completions.Add("$($generatedEntry.Entry).$name") | Out-Null
                    }
                }
            }
        }

        foreach ($item in (Get-ConfigMapInternalCommandPaths -Map $userMap).GetEnumerator()) {
            if (-not ([string]$item.Key).StartsWith($completionWord, [System.StringComparison]::OrdinalIgnoreCase)) {
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
}

Set-Alias -Name "qbuild" -Value "Invoke-QBuild" -Force

# Registered rather than declared as [ArgumentCompleter] attributes: attribute scriptblocks
# run outside the module, so they cannot reach its private helpers. These scriptblocks are
# bound to the scope that loads this file (the module, or the caller of configmap.ps1).
# Registering for Invoke-QBuild also covers the qbuild alias.
Register-ArgumentCompleter -CommandName Invoke-QBuild -ParameterName entry -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    Get-QBuildEntryCompletion -WordToComplete $wordToComplete -FakeBoundParameters $fakeBoundParameters
}

Register-ArgumentCompleter -CommandName Invoke-QBuild -ParameterName ProcessAction -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    try {
        Get-QBuildProcessArgumentCompletion -CommandAst $commandAst -FakeBoundParameters $fakeBoundParameters -Word $wordToComplete -Position Action
    }
    catch {
        @()
    }
}

Register-ArgumentCompleter -CommandName Invoke-QBuild -ParameterName ProcessValue -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    try {
        Get-QBuildProcessArgumentCompletion -CommandAst $commandAst -FakeBoundParameters $fakeBoundParameters -Word $wordToComplete -Position Value
    }
    catch {
        @()
    }
}

Register-ArgumentCompleter -CommandName Invoke-QBuild -ParameterName RemainingArguments -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    try {
        $position = Get-QBuildRemainingArgumentPosition -CommandAst $commandAst -FakeBoundParameters $fakeBoundParameters -Word $wordToComplete
        if (-not $position) { return @() }
        Get-QBuildProcessArgumentCompletion -CommandAst $commandAst -FakeBoundParameters $fakeBoundParameters -Word $wordToComplete -Position $position
    }
    catch {
        @()
    }
}
