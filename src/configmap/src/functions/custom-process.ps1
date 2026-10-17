#requires -version 7.0

# Handler names are matched ordinal-ignore-case.
# 'exec' is the built-in default process (normal map entry exec). It is never
# handed to an external CLI. Other registered handlers stay in-process.
# Null GetDynamicParam or WriteListEntry keeps the host fallback for that slot.
# Only an unregistered, non-builtin name is handed to an external process command.
#
# Process-type aliases (legacy → canonical): qrun→steps, qconf→options.
# Canonical names are what maps should declare; legacy values still normalize.
$script:ConfigMapDefaultProcessName = 'exec'
$script:ConfigMapProcessHandlers = [System.Collections.Generic.Dictionary[string, hashtable]]::new(
    [StringComparer]::OrdinalIgnoreCase
)
$script:ConfigMapProcessNameAliases = [System.Collections.Generic.Dictionary[string, string]]::new(
    [StringComparer]::OrdinalIgnoreCase
)
$script:ConfigMapProcessNameAliases['qrun'] = 'steps'
$script:ConfigMapProcessNameAliases['qconf'] = 'options'

# Canonical process type → standalone CLI command (unchanged public aliases).
$script:ConfigMapProcessCliNames = [System.Collections.Generic.Dictionary[string, string]]::new(
    [StringComparer]::OrdinalIgnoreCase
)
$script:ConfigMapProcessCliNames['steps'] = 'qrun'
$script:ConfigMapProcessCliNames['options'] = 'qconf'

function Get-ConfigMapProcessCanonicalName {
    param(
        [AllowEmptyString()]
        [string]$ProcessName
    )

    if ([string]::IsNullOrWhiteSpace($ProcessName)) {
        return $ProcessName
    }

    if ($script:ConfigMapProcessNameAliases.ContainsKey($ProcessName)) {
        return $script:ConfigMapProcessNameAliases[$ProcessName]
    }

    return $ProcessName
}

function Test-ConfigMapProcessNameMatch {
    param(
        [AllowEmptyString()]
        [string]$Left,
        [AllowEmptyString()]
        [string]$Right
    )

    return (Get-ConfigMapProcessCanonicalName -ProcessName $Left) -eq (Get-ConfigMapProcessCanonicalName -ProcessName $Right)
}

function Get-ConfigMapProcessCliName {
    <#
    .SYNOPSIS
        CLI command for a process type (steps→qrun, options→qconf). Identity otherwise.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ProcessName
    )

    $canonical = Get-ConfigMapProcessCanonicalName -ProcessName $ProcessName
    if ([string]::IsNullOrWhiteSpace($canonical)) {
        return $canonical
    }

    if ($script:ConfigMapProcessCliNames.ContainsKey($canonical)) {
        return $script:ConfigMapProcessCliNames[$canonical]
    }

    return $canonical
}

function Register-ConfigMapProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [scriptblock]$Invoke,
        [scriptblock]$GetDynamicParam,
        [scriptblock]$WriteListEntry
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Process handler name is required.'
    }

    $script:ConfigMapProcessHandlers[$Name] = @{
        Name            = $Name
        Invoke          = $Invoke
        GetDynamicParam = $GetDynamicParam
        WriteListEntry  = $WriteListEntry
    }
}

function Get-ConfigMapProcessHandler {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    $canonical = Get-ConfigMapProcessCanonicalName -ProcessName $Name
    if (-not $script:ConfigMapProcessHandlers.ContainsKey($canonical)) {
        return $null
    }

    return $script:ConfigMapProcessHandlers[$canonical]
}

function Unregister-ConfigMapProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    [void]$script:ConfigMapProcessHandlers.Remove($Name)
}

function New-ConfigMapProcessContext {
    <#
    .SYNOPSIS
        Context passed to an in-process handler.

        dynamicparam leaves OperationContext empty. process fills every field.
    #>
    param(
        $Map,
        $UserMap,
        $MapArgument,
        $Entry,
        $Command,
        $Invocation,
        $OperationContext,
        $BoundParameters,
        [AllowEmptyString()]
        [string]$ProcessAction,
        [AllowEmptyString()]
        [string]$ProcessValue,
        [AllowNull()]
        [string[]]$RemainingArguments
    )

    $passthrough = @($RemainingArguments | Where-Object { $null -ne $_ })
    return @{
        Map                = $Map
        UserMap            = $UserMap
        MapArgument        = $MapArgument
        Entry              = $Entry
        Command            = $Command
        Invocation         = $Invocation
        OperationContext   = $OperationContext
        BoundParameters    = $BoundParameters
        ProcessAction      = $ProcessAction
        ProcessValue       = $ProcessValue
        RemainingArguments = $passthrough
    }
}

function Get-ConfigMapProcessPassthrough {
    param(
        [AllowEmptyString()]
        [string]$ProcessAction,
        [AllowEmptyString()]
        [string]$ProcessValue,
        [AllowNull()]
        [string[]]$RemainingArguments
    )

    return @(
        $ProcessAction
        $ProcessValue
        $RemainingArguments
    ) | Where-Object { $null -ne $_ -and "$_" -ne '' }
}

function Test-ConfigMapProcessIsBuiltin {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ProcessName
    )

    if ([string]::IsNullOrWhiteSpace($ProcessName)) {
        return $true
    }

    $canonical = Get-ConfigMapProcessCanonicalName -ProcessName $ProcessName
    return $canonical -eq $script:ConfigMapDefaultProcessName
}

function Test-ConfigMapProcessResolvesToHost {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName
    )

    $cmd = Get-Command $ProcessName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return $false
    }
    if ($cmd.CommandType -eq 'Alias') {
        $cmd = $cmd.ResolvedCommand
    }
    return $cmd.Name -eq 'Invoke-QBuild'
}

function Test-ConfigMapProcessCannotDelegate {
    <#
    .SYNOPSIS
        True when a process name must not be handed to an external CLI.
        Covers the builtin 'exec' default and names that resolve to the qbuild host.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ProcessName
    )

    if (Test-ConfigMapProcessIsBuiltin -ProcessName $ProcessName) {
        return $true
    }

    return Test-ConfigMapProcessResolvesToHost -ProcessName $ProcessName
}

function Invoke-ConfigMapExternalProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $true)]
        [string]$Entry,
        $Map,
        [hashtable]$BoundParameters,
        [AllowEmptyString()]
        [string]$ProcessAction,
        [AllowEmptyString()]
        [string]$ProcessValue,
        [string[]]$RemainingArguments
    )

    $resolvedMapPath = Resolve-MapPath -Map $Map
    if (-not $resolvedMapPath) {
        throw "Cannot delegate process '$ProcessName' for entry '$Entry': the map has no _sourceFile."
    }
    if (Test-ConfigMapProcessCannotDelegate -ProcessName $ProcessName) {
        throw "Cannot delegate process '$ProcessName' for entry '$Entry': no in-process handler is registered."
    }

    $passthrough = Get-ConfigMapProcessPassthrough `
        -ProcessAction $ProcessAction `
        -ProcessValue $ProcessValue `
        -RemainingArguments $RemainingArguments
    $splat = ConvertTo-ConfigMapProcessSplat `
        -MapPath $resolvedMapPath `
        -Entry $Entry `
        -BoundParameters $BoundParameters `
        -RemainingArguments $passthrough

    Invoke-ConfigMapProcessCli `
        -ProcessName (Get-ConfigMapProcessCliName -ProcessName $ProcessName) `
        -Splat $splat
}

function Get-EntryProcess {
    param(
        $Entry,
        [string]$Default = 'exec'
    )

    if (
        $Entry -is [System.Collections.IDictionary] -and
        $Entry._settings -is [System.Collections.IDictionary] -and
        $Entry._settings.Contains('process') -and
        $Entry._settings.process
    ) {
        return Get-ConfigMapProcessCanonicalName -ProcessName ([string]$Entry._settings.process)
    }
    return Get-ConfigMapProcessCanonicalName -ProcessName $Default
}

function Invoke-ConfigMapProcessFromContext {
    <#
    .SYNOPSIS
        Run a process CLI (qrun/qconf) from an in-process handler context via path-only -map.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Context,
        [Parameter(Mandatory = $true)]
        [string]$CliName
    )

    $mapPath = Resolve-MapPath -Map $Context.Map
    if (-not $mapPath) {
        throw "Cannot delegate process '$CliName' for entry '$($Context.Entry)': the map has no _sourceFile."
    }

    $passthrough = Get-ConfigMapProcessPassthrough `
        -ProcessAction $Context.ProcessAction `
        -ProcessValue $Context.ProcessValue `
        -RemainingArguments $Context.RemainingArguments
    $splat = ConvertTo-ConfigMapProcessSplat `
        -MapPath $mapPath `
        -Entry $Context.Entry `
        -BoundParameters $Context.BoundParameters `
        -RemainingArguments $passthrough

    $cmd = Resolve-ConfigMapProcessCommand -ProcessName $CliName
    $global:LASTEXITCODE = 0
    & $cmd @splat
    if ($global:LASTEXITCODE -ne 0) {
        throw "Process command '$CliName' exited with code $global:LASTEXITCODE."
    }
}

function Get-ConfigMapProcessDynamicParamFromCli {
    param(
        [Parameter(Mandatory = $true)]
        $Context,
        [Parameter(Mandatory = $true)]
        [string]$CliName
    )

    $mapPath = Resolve-MapPath -Map $Context.Map
    $followHint = [bool]($Context.BoundParameters -and $Context.BoundParameters['Follow'])
    if (-not $mapPath) {
        return Get-ProcessDynamicParam -Map $Context.Map -ProcessKey $Context.Entry -Follow:$followHint
    }
    return New-ConfigMapProcessDynamicParam `
        -ProcessName $CliName `
        -MapPath $mapPath `
        -Map $Context.Map `
        -Entry $Context.Entry `
        -Follow:$followHint `
        -ProcessAction $Context.ProcessAction `
        -ProcessValue $Context.ProcessValue `
        -RemainingArguments $Context.RemainingArguments
}

function Write-ConfigMapProcessListEntryFromCli {
    param(
        [Parameter(Mandatory = $true)]
        $ListContext,
        [Parameter(Mandatory = $true)]
        [string]$CliName
    )

    $mapPath = Resolve-MapPath -Map $ListContext.Map
    if (-not $mapPath) {
        return
    }
    $splat = ConvertTo-ConfigMapProcessSplat `
        -MapPath $mapPath `
        -Command 'list' `
        -RemainingArguments @($ListContext.Name)
    $cmd = Resolve-ConfigMapProcessCommand -ProcessName $CliName
    & $cmd @splat
}

function Register-ConfigMapCliProcess {
    <#
    .SYNOPSIS
        Register an in-process handler that forwards to a standalone process CLI.
        Scriptblocks call helpers by name (no GetNewClosure) so they stay in module scope.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$CliName
    )

    $script:ConfigMapProcessCliNames[$Name] = $CliName

    Register-ConfigMapProcess -Name $Name -Invoke {
        param($Context)
        $cli = Get-ConfigMapProcessCliName -ProcessName (
            Get-ConfigMapSettingsForPath -Map $Context.Map -Path $Context.Entry -OperationContext $Context.OperationContext
        ).Process
        Invoke-ConfigMapProcessFromContext -Context $Context -CliName $cli
    } -GetDynamicParam {
        param($Context)
        $cli = Get-ConfigMapProcessCliName -ProcessName (
            Get-ConfigMapSettingsForPath -Map $Context.Map -Path $Context.Entry
        ).Process
        Get-ConfigMapProcessDynamicParamFromCli -Context $Context -CliName $cli
    } -WriteListEntry {
        param($ListContext)
        $cli = Get-ConfigMapProcessCliName -ProcessName (
            Get-ConfigMapSettingsForPath -Map $ListContext.Map -Path $ListContext.Name -OperationContext $ListContext.OperationContext
        ).Process
        Write-ConfigMapProcessListEntryFromCli -ListContext $ListContext -CliName $cli
    }
}

function Resolve-MapPath {
    <#
    .SYNOPSIS
        Get the source file path for process CLI -map handoff.
    #>
    param(
        $Map
    )

    if ($Map -is [System.Collections.IDictionary] -and $Map._sourceFile) {
        return [string]$Map._sourceFile
    }
    return $null
}

function Resolve-ConfigMapProcessCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName
    )

    $cmd = Get-Command $ProcessName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Process command '$ProcessName' not found on PATH / session. Install or import it so '& $ProcessName' works."
    }
    if ($cmd.CommandType -eq 'Alias') {
        $cmd = $cmd.ResolvedCommand
    }
    return $cmd
}

function Get-QBuildProcessCompletionContext {
    param(
        $CommandAst,
        [hashtable]$FakeBoundParameters
    )

    $elements = @($CommandAst.CommandElements | ForEach-Object { [string]$_.Extent.Text })
    $mapInput = $FakeBoundParameters.map
    $positionals = [System.Collections.Generic.List[string]]::new()

    for ($index = 1; $index -lt $elements.Count; $index++) {
        $token = $elements[$index]
        if ($token -eq '-map' -and $index + 1 -lt $elements.Count) {
            if (-not $mapInput) {
                $mapInput = $elements[++$index].Trim("'`"")
            }
            else {
                $index++
            }
            continue
        }
        if ($token.StartsWith('-')) { continue }
        $positionals.Add($token.Trim("'`""))
    }

    return [pscustomobject]@{
        MapInput      = $mapInput
        Entry         = if ($FakeBoundParameters.entry) { [string]$FakeBoundParameters.entry } elseif ($positionals.Count -gt 0) { $positionals[0] } else { $null }
        ProcessAction = if ($FakeBoundParameters.ProcessAction) { [string]$FakeBoundParameters.ProcessAction } elseif ($positionals.Count -gt 1) { $positionals[1] } else { $null }
        Positionals   = @($positionals)
    }
}

function Get-QBuildRemainingArgumentPosition {
    param(
        $CommandAst,
        [hashtable]$FakeBoundParameters,
        [AllowEmptyString()]
        [string]$Word = ''
    )

    if (-not $CommandAst) { return $null }

    $context = Get-QBuildProcessCompletionContext -CommandAst $CommandAst -FakeBoundParameters $FakeBoundParameters
    $positionals = @($context.Positionals)
    $slot = $positionals.Count
    $normalizedWord = $Word.Trim("'`"")
    if ($normalizedWord -ne '' -and $slot -gt 0 -and $positionals[-1] -eq $normalizedWord) {
        $slot = $slot - 1
    }

    switch ($slot) {
        1 { return 'Action' }
        2 { return 'Value' }
        default { return $null }
    }
}

function Get-QBuildProcessArgumentCompletion {
    param(
        $CommandAst,
        [hashtable]$FakeBoundParameters,
        [AllowEmptyString()]
        [string]$Word = '',
        [ValidateSet('Action', 'Value')]
        [string]$Position
    )

    $context = Get-QBuildProcessCompletionContext -CommandAst $CommandAst -FakeBoundParameters $FakeBoundParameters
    if (-not $context.Entry) { return @() }
    if ($Position -eq 'Value' -and -not $context.ProcessAction) { return @() }

    $processMap = Import-ConfigMap -Map $context.MapInput -Fallback "./.build.map.ps1" | Assert-ConfigMap
    $settings = Get-ConfigMapSettingsForPath -Map $processMap -Path $context.Entry
    if (Test-ConfigMapProcessIsBuiltin -ProcessName $settings.Process) { return @() }

    $mapPath = Resolve-MapPath -Map $processMap
    if (-not $mapPath) { return @() }

    $complete = @{
        ProcessName = Get-ConfigMapProcessCliName -ProcessName $settings.Process
        MapPath     = $mapPath
        Entry       = $context.Entry
        Word        = $Word
    }
    if ($Position -eq 'Value') {
        $complete.RemainingArguments = @($context.ProcessAction)
    }
    return Get-ConfigMapProcessCompleteWord @complete
}

function Invoke-ConfigMapProcessComplete {
    <#
    .SYNOPSIS
        Run '<process> !complete …'; return trimmed lines, or $null if unsupported/missing.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $true)]
        [string]$MapPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$CompleteArgs
    )

    if (Test-ConfigMapProcessCannotDelegate -ProcessName $ProcessName) {
        return $null
    }

    try {
        $cmd = Resolve-ConfigMapProcessCommand -ProcessName $ProcessName
    }
    catch {
        return $null
    }

    $global:LASTEXITCODE = 0
    $output = & $cmd -map $MapPath '!complete' @CompleteArgs 2>$null
    if ($global:LASTEXITCODE -eq 2) {
        return $null
    }

    return @(
        @($output) |
            ForEach-Object { "$_".Trim() } |
            Where-Object { $_ }
    )
}

function New-ConfigMapOpaqueDynamicParam {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [type]$ParameterType = [switch],
        [switch]$DontShow
    )

    $attribute = New-Object System.Management.Automation.ParameterAttribute
    if ($DontShow) {
        $attribute.DontShow = $true
    }
    $attributes = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
    $attributes.Add($attribute)
    return New-Object System.Management.Automation.RuntimeDefinedParameter($Name, $ParameterType, $attributes)
}

function ConvertTo-ConfigMapProcessSplat {
    <#
    .SYNOPSIS
        Build a hashtable splat for '& process @splat' (path-only -map + opaque bound params).

        Hashtable splat is required so -Force / -Follow bind as switches; a string[] argv
        splat passes '-Force' as a literal remaining argument.

        Run:    -Entry <path>          →  process -map <file> -entry <path> …
        Verb:   -Command list …        →  process -map <file> -command list …
        Both:   -Command !complete -Entry x → process !complete -entry x
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$MapPath,
        [string]$Command,
        [AllowEmptyString()]
        [string]$Entry,
        [hashtable]$BoundParameters,
        [string[]]$RemainingArguments,
        [string[]]$SkipKeys = @(
            'entry', 'command', 'map', 'ProcessAction', 'ProcessValue', 'RemainingArguments',
            'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
            'ErrorVariable', 'WarningVariable', 'InformationVariable',
            'OutVariable', 'OutBuffer', 'PipelineVariable', 'ProgressAction'
        )
    )

    $splat = @{
        map = $MapPath
    }

    if ($Command) {
        $splat['command'] = $Command
    }

    if ($PSBoundParameters.ContainsKey('Entry') -and $null -ne $Entry) {
        $splat['entry'] = $Entry
    }

    if ($BoundParameters) {
        foreach ($key in @($BoundParameters.Keys)) {
            if ($key -in $SkipKeys) { continue }
            if ($key -like '_*') { continue }

            $val = $BoundParameters[$key]
            if ($val -is [System.Management.Automation.SwitchParameter]) {
                if ($val.IsPresent) {
                    $splat[$key] = $true
                }
                continue
            }
            if ($val -is [bool]) {
                if ($val) {
                    $splat[$key] = $true
                }
                continue
            }

            $splat[$key] = $val
        }
    }

    $passthrough = @($RemainingArguments | Where-Object { $null -ne $_ })
    if ($passthrough.Count -gt 0) {
        $splat['RemainingArguments'] = $passthrough
    }

    return $splat
}

function Invoke-ConfigMapProcessCli {
    <#
    .SYNOPSIS
        Invoke a process command via the call operator with path-only -map handoff.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $true)]
        [hashtable]$Splat
    )

    if (Test-ConfigMapProcessCannotDelegate -ProcessName $ProcessName) {
        throw "Cannot delegate process '$ProcessName': no in-process handler is registered."
    }

    $cmd = Resolve-ConfigMapProcessCommand -ProcessName $ProcessName
    $global:LASTEXITCODE = 0
    & $cmd @Splat
    if ($global:LASTEXITCODE -ne 0) {
        throw "Process command '$ProcessName' exited with code $global:LASTEXITCODE."
    }
}

function Get-ConfigMapProcessNamesInMap {
    <#
    .SYNOPSIS
        Distinct process names declared on top-level entries that have no in-process handler.
        Skips the builtin 'exec' default and names that resolve to the qbuild host.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        $OperationContext
    )

    if (-not $OperationContext) {
        $OperationContext = New-ConfigMapOperationContext
    }

    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @($Map.Keys)) {
        if ([string]$key -like '_*') { continue }
        $resolved = Get-MapEntry $Map $key -language 'build' -OperationContext $OperationContext
        $proc = Get-EntryProcess $resolved
        if (
            $proc -and
            -not (Get-ConfigMapProcessHandler -Name $proc) -and
            -not (Test-ConfigMapProcessCannotDelegate -ProcessName $proc)
        ) {
            [void]$names.Add((Get-ConfigMapProcessCanonicalName -ProcessName $proc))
        }
    }
    return @($names | Sort-Object)
}

function Get-ConfigMapProcessCompleteParams {
    <#
    .SYNOPSIS
        Discover opaque parameter names via '<process> !complete -params -entry …'.
        Returns $null when unsupported (exit 2 / missing command).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $true)]
        [string]$MapPath,
        [Parameter(Mandatory = $true)]
        [string]$Entry
    )

    return Invoke-ConfigMapProcessComplete -ProcessName $ProcessName -MapPath $MapPath -CompleteArgs @{
        Params = $true
        Entry  = $Entry
    }
}

function Get-ConfigMapProcessCompleteWord {
    <#
    .SYNOPSIS
        Entry/token completion via '<process> !complete -word <prefix> [-entry …]'.
        Returns $null when unsupported (exit 2 / missing command).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $true)]
        [string]$MapPath,
        [AllowEmptyString()]
        [string]$Word = '',
        [string]$Entry,
        [string[]]$RemainingArguments
    )

    $completeArgs = @{ Word = $Word }
    if ($Entry) {
        $completeArgs['Entry'] = $Entry
    }
    if ($RemainingArguments) {
        $completeArgs['RemainingArguments'] = @($RemainingArguments)
    }

    return Invoke-ConfigMapProcessComplete -ProcessName $ProcessName -MapPath $MapPath -CompleteArgs $completeArgs
}

function Test-ConfigMapProcessPositionalOptionKey {
    <#
    .SYNOPSIS
        True when the option key was already supplied positionally (set <option> …).
    #>
    param(
        [string]$ProcessAction,
        [string]$ProcessValue,
        [string[]]$RemainingArguments
    )

    if (-not [string]::IsNullOrWhiteSpace($ProcessValue)) {
        return $true
    }

    $tokens = @(
        @($ProcessAction) + @($RemainingArguments) |
            Where-Object { $null -ne $_ -and "$_" -ne '' }
    )
    return ($tokens.Count -ge 2 -and $tokens[0] -eq 'set')
}

function New-ConfigMapProcessDynamicParam {
    <#
    .SYNOPSIS
        Build dynparams from !complete -params names; type step params from the map when available.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $true)]
        [string]$MapPath,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        [Parameter(Mandatory = $true)]
        [string]$Entry,
        [switch]$Follow,
        [string]$ProcessAction,
        [string]$ProcessValue,
        [string[]]$RemainingArguments
    )

    $names = Get-ConfigMapProcessCompleteParams -ProcessName $ProcessName -MapPath $MapPath -Entry $Entry
    $typed = Get-ProcessDynamicParam -Map $Map -ProcessKey $Entry -Follow:$Follow
    if (-not $typed) {
        $typed = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    }

    # Conf-style set scripts (process=options) expose opaque params after ctx/key/value.
    $setParams = Get-EntryDynamicParam $Map "$Entry.set" -skip 3 -bound @{}
    if ($setParams) {
        foreach ($name in @($setParams.Keys)) {
            if (-not $typed.ContainsKey($name)) {
                $typed.Add($name, $setParams[$name])
            }
        }
    }

    # Positional `set <option>` already supplied the option key — drop -value entirely
    # when we can see it (runtime). Tab completion often cannot see RemainingArguments in
    # dynamicparam, so -value is also DontShow below and stays typeable but hidden.
    $hideValue = Test-ConfigMapProcessPositionalOptionKey `
        -ProcessAction $ProcessAction `
        -ProcessValue $ProcessValue `
        -RemainingArguments $RemainingArguments

    if ($null -eq $names) {
        if ($hideValue -and $typed.ContainsKey('value')) {
            $typed.Remove('value') | Out-Null
        }
        return $typed
    }

    $merged = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    foreach ($name in $names) {
        if ($merged.ContainsKey($name)) { continue }
        if ($hideValue -and $name -eq 'value') { continue }

        $parameterType = [switch]
        $source = $null
        if ($typed -and $typed.ContainsKey($name)) {
            $source = $typed[$name]
            $parameterType = $source.ParameterType
        }
        else {
            try {
                $processCommand = Resolve-ConfigMapProcessCommand -ProcessName $ProcessName
                $processParameter = $processCommand.Parameters[$name]
                if ($processParameter -and $processParameter.ParameterType) {
                    $parameterType = $processParameter.ParameterType
                }
            }
            catch {
                # Keep the protocol's backwards-compatible switch fallback.
            }
        }

        # Prefer set <option>; keep -value bindable but out of -<tab> suggestions.
        if ($name -eq 'value') {
            $merged.Add($name, (New-ConfigMapOpaqueDynamicParam -Name $name -ParameterType $parameterType -DontShow))
        }
        elseif ($source) {
            $merged.Add($name, $source)
        }
        else {
            $merged.Add($name, (New-ConfigMapOpaqueDynamicParam -Name $name -ParameterType $parameterType))
        }
    }
    return $merged
}
