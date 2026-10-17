function Invoke-EntryWrapper {
    param(
        [string]$MainCommand,
        [string]$TargetKey,
        $TargetEntry,
        [string]$Command,
        [hashtable]$Bound,
        [string[]]$RemainingArguments
    )

    $context = @{
        MainCommand        = $MainCommand
        TargetKey          = $TargetKey
        TargetEntry        = $TargetEntry
        Command            = $Command
        Bound              = $Bound
        RemainingArguments = $RemainingArguments
    }

    $hookResult = Invoke-ConfigMapPluginHooks -HookName 'InvokeEntryWrapper' -Context $context
    if ($hookResult.Handled) {
        return $hookResult.Result
    }

    Invoke-EntryCommand -entry $TargetEntry -key $Command -bound $Bound
}

function Invoke-EntryCommand($entry, $key = "exec", $ordered = @(), $bound = @{}) {
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
            Invoke-WithEntrySettings -Map $entry -EntryKey "$subCommandName" -Entry $subEntry -ScriptBlock {
                Invoke-EntryCommand -entry $subEntry -ordered $ordered -bound $bound
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
    try {
        pushd $baseDir
        return & $command @ordered @filtered
    }
    finally {
        popd
    }
}

# function Invoke-Entry(
#     [ValidateScript({
#             $_ -is [string] -or $_ -is [System.Collections.IDictionary]
#         })]
#     $map,
#     $entry,
#     $bound
# ) {
#     $map = Import-ConfigMap $map

#     $targets = Get-MapEntries $map $entry
#     Write-Verbose "running targets: $($targets.Key)"

#     @($targets) | % {
#         Write-Verbose "running entry '$($_.key)'"
#         Invoke-EntryCommand -entry $_.value -key "exec" -bound $bound
#     }
# }

function Invoke-Set($entry, $bound = @{}, $extra = @()) {
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

    Invoke-EntryCommand $entry "set" -ordered @("", $bound.key, $bound.value) -bound $bound
}

function Invoke-Get($entry, $bound = @{}) {
    # use ordered parameters, just in case the handler has different parameter names
    Invoke-EntryCommand $entry "get" -ordered @("", $bound.options) -bound $bound
}
