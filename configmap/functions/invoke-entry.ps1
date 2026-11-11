function Invoke-EntryWrapper {
    param(
        [string]$MainCommand,
        [string]$TargetKey,
        $TargetEntry,
        [string]$Command,
        [hashtable]$Bound,
        [string[]]$RemainingArguments,
        [hashtable]$RunContext
    )

    if (-not $RunContext) {
        $RunContext = New-ConfigMapCurrentRunContext -Entry $TargetEntry
    }

    $context = @{
        MainCommand        = $MainCommand
        TargetKey          = $TargetKey
        TargetEntry        = $TargetEntry
        Command            = $Command
        Bound              = $Bound
        RemainingArguments = $RemainingArguments
        RunContext         = $RunContext
        Settings           = $RunContext.Settings
    }

    $hookResult = Invoke-ConfigMapPluginHooks -HookName 'InvokeEntryWrapper' -Context $context
    if ($hookResult.Handled) {
        return $hookResult.Result
    }

    Invoke-EntryCommand -entry $TargetEntry -key $Command -bound $Bound -RunContext $RunContext
}

function New-ConfigMapCurrentRunContext {
    <#
    .SYNOPSIS
        Run context for a caller that passed none, such as a script calling Invoke-EntryCommand,
        built from the settings that script is running with.
    #>
    param($Entry)

    $context = New-ConfigMapRunContext -BaseSettings (Get-ConfigMapSettings)
    $context.Entry = $Entry
    return $context
}

function Invoke-EntryCommand($entry, $key = "exec", $ordered = @(), $bound = @{}, [hashtable]$RunContext) {
    if (-not $RunContext) {
        $RunContext = New-ConfigMapCurrentRunContext -Entry $entry
    }

    $command = Get-EntryCommand $entry $key

    if (!$command) {
        throw "Command '$key' not found"
    }

    # Handle exec as list of subcommand names
    if ($command -is [array]) {
        if ($entry -isnot [System.Collections.IDictionary]) {
            throw "Entry must be a hashtable when exec is an array"
        }

        $commandList = $command -join ", "
        Write-Host "Resolved to commands: [$commandList]" -ForegroundColor Cyan

        for ($i = 0; $i -lt $command.Count; $i++) {
            $subCommandName = $command[$i]
            Write-Host "[$($i + 1)/$($command.Count)] Running '$subCommandName'..." -ForegroundColor Yellow

            if (!$entry.$subCommandName) {
                throw "Subcommand '$subCommandName' not found in entry"
            }

            $subEntry = $entry.$subCommandName
            $subContext = New-ConfigMapEntryContext -Parent $RunContext -Map $entry -EntryKey "$subCommandName" -Entry $subEntry
            Invoke-WithRunContext -Context $subContext -ScriptBlock {
                Invoke-EntryCommand -entry $subEntry -ordered $ordered -bound $bound -RunContext $subContext
            }
        }

        return
    }

    # Normal scriptblock execution
    $scriptArgs = Get-ScriptArgs $command -exclude @()

    if ($command -isnot [scriptblock]) {
        throw "Entry '$key' of type $($command.GetType().Name) is not supported"
    }

    if (!$bound) { $bound = @{} }
    if (!$bound._context) { $bound._context = @{} }
    # Passthrough arguments only reach an entry through its _context parameter.
    if ('_context' -notin $scriptArgs.Keys) {
        $dropped = @($bound._context.additionalArgs | Where-Object { "$_" -match '^-\w' })
        if ($dropped.Count -gt 0) {
            Write-Warning "Ignoring unknown parameter(s): $($dropped -join ', '). The command declares no such parameter."
        }
    }
    if (!$bound._context.self) { $bound._context.self = $entry }
    if (
        -not $bound._context.base `
            -and $entry -is [System.Collections.IDictionary] `
            -and $entry.Contains('_internal') `
            -and $entry._internal -is [System.Collections.IDictionary] `
            -and $entry._internal.Contains('base')
    ) {
        $bound._context.base = $entry._internal.base
    }

    $baseDir = $null
    if ($entry -is [System.Collections.IDictionary] -and $entry._baseDir) {
        $baseDir = $entry._baseDir
    }
    if (!$baseDir) {
        $baseDir = Get-Location
    }
    if (!$bound._context.workDir) { $bound._context.workDir = (Get-Location).Path }
    # Directory of the map file that defined this entry, even when running in workDir.
    $bound._context.mapDir = "$baseDir"
    # Set on every call: $bound is shared across steps, and each entry has its own settings.
    $bound._context.settings = ConvertTo-ConfigMapReadOnlySettings -Settings $RunContext.Settings
    # useWorkDir: run in the caller's directory instead of the map's.
    if (Test-ConfigMapFeatureEnabled -Name UseWorkDir -Settings $RunContext.Settings) {
        $baseDir = $bound._context.workDir
    }

    # Always pass special parameters (_context, _self) plus any that match script params
    $specialParams = @("_context", "_self") | ? { $scriptArgs.Keys -contains $_ }
    $filtered = @{}
    Write-Verbose "script args: $( $scriptArgs.Keys -join ', ' )"
    foreach ($boundKey in $bound.Keys) {
        if ($boundKey -in $scriptArgs.Keys -or $boundKey -in $specialParams) {
            Write-Verbose "adding '$boundKey'"
            $filtered[$boundKey] = $bound[$boundKey]
        }
        else {
            Write-Verbose "skipping '$boundKey'"
        }
    }

    Write-Verbose "ordered args: $( $ordered -join ', ' )"
    Write-Verbose "filtered args: $( $filtered.Keys -join ', ' )"
    Assert-EntryValueSourceArgument -Entry $entry -Command $command -Bound $filtered
    # ValidateSet('@sibling') values are checked above or by the dynamic parameter; the literal
    # attribute would reject every real value when the block runs.
    $siblingValidateSet = '\[\s*ValidateSet\(\s*[''"]@\w+[''"]\s*\)\s*\]'
    if ($command.ToString() -match $siblingValidateSet) {
        $command = [scriptblock]::Create(($command.ToString() -replace $siblingValidateSet, ''))
    }

    try {
        pushd $baseDir
        return & $command @ordered @filtered
    }
    finally {
        popd
    }
}

function Invoke-Set($entry, $bound = @{}, $extra = @(), [hashtable]$RunContext) {
    # use ordered parameters, just in case the handler has different parameter names
    # Nameless leftovers after the option key (e.g. `set local tenant_1`) bind by name to
    # set params beyond ctx/key/value. Prefer already-bound names (e.g. -tenant).
    if (-not $bound) { $bound = @{} }
    $extras = @($extra | Where-Object { $null -ne $_ -and "$_" -ne '' })
    if ($extras.Count -gt 0) {
        $setCommand = Get-EntryCommand $entry 'set'
        if ($setCommand -is [scriptblock]) {
            $opaqueParams = Get-ScriptArgs $setCommand -skip 3 -exclude @('$_context', '$_self')
            $index = 0
            foreach ($name in @($opaqueParams.Keys)) {
                if ($index -ge $extras.Count) { break }
                if ($bound.ContainsKey($name)) { continue }
                $bound[$name] = $extras[$index]
                $index++
            }
        }
    }

    Invoke-EntryCommand $entry "set" -ordered @("", $bound.key, $bound.value) -bound $bound -RunContext $RunContext
}

function Invoke-Get($entry, $bound = @{}, [hashtable]$RunContext) {
    # use ordered parameters, just in case the handler has different parameter names
    Invoke-EntryCommand $entry "get" -ordered @("", $bound.options) -bound $bound -RunContext $RunContext
}
