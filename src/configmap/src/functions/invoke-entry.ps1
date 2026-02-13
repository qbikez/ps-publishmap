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
        
        $results = @()
        foreach ($subCommandName in $command) {
            Write-Verbose "executing subcommand '$subCommandName' from exec list"
            
            if (!$entry.$subCommandName) {
                throw "Subcommand '$subCommandName' not found in entry"
            }
            
            $subEntry = $entry.$subCommandName
            $result = Invoke-EntryCommand -entry $subEntry -ordered $ordered -bound $bound
            $results += $result
        }
        
        return $results
    }
    
    # Normal scriptblock execution
    $scriptArgs = Get-ScriptArgs $command -exclude @()

    if ($command -isnot [scriptblock]) {
        throw "Entry '$key' of type $($command.GetType().Name) is not supported"
    }

    if (!$bound) { $bound = @{} }
    if (!$bound._context) { $bound._context = @{} }
    if (!$bound._context.self) { $bound._context.self = $entry }

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

    $baseDir = $null
    if (!$baseDir -and $entry -is [System.Collections.IDictionary] -and $entry._baseDir) {
        $baseDir = $entry._baseDir
    }
    if (!$baseDir) {
        $baseDir = Get-Location
    }
    
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

function Invoke-Set($entry, $bound = @{}) {
    # use ordered parameters, just in case the handler has different parameter names
    Invoke-EntryCommand $entry "set" -ordered @("", $bound.key, $bound.value) -bound $bound
}

function Invoke-Get($entry, $bound = @{}) {
    # use ordered parameters, just in case the handler has different parameter names
    Invoke-EntryCommand $entry "get" -ordered @("", $bound.options) -bound $bound
}
