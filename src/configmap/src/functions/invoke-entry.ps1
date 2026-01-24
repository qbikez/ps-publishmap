function Invoke-EntryCommand($entry, $key, $ordered = @(), $bound = @{}) {
    $command = Get-EntryCommand $entry $key
    $scriptArgs = Get-ScriptArgs $command

    if (!$command) {
        throw "Command '$key' not found"
    }
    if ($command -isnot [scriptblock]) {
        throw "Entry '$key' of type $($command.GetType().Name) is not supported"
    }

    if (!$bound) { $bound = @{} }
    if (!$bound._context) { $bound._context = @{} }
    if (!$bound._context.self) { $bound._context.self = $entry }

    # Always pass special parameters (_context, _self) plus any that match script params
    $specialParams = @("_context", "_self")
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

    return & $command @ordered @filtered
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

function Invoke-Set($entry, $bound = @{}) {
    # use ordered parameters, just in case the handler has different parameter names
    Invoke-EntryCommand $entry "set" -ordered @("", $bound.key, $bound.value) -bound $bound
}

function Invoke-Get($entry, $bound = @{}) {
    # use ordered parameters, just in case the handler has different parameter names
    Invoke-EntryCommand $entry "get" -ordered @("", $bound.options) -bound $bound
}
