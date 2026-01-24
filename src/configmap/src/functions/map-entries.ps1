function Get-MapEntries(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -or $_ -is [array]
        })]
    $map,
    $keys,
    [switch][bool]$flatten = $false,
    [switch][bool]$leafsOnly = $false,
    $separator = ".",
    $reservedKeys = $null
) {
    $results = @()

    $completions = Get-CompletionList $map -flatten:$flatten -leafsOnly:$leafsOnly -separator:$separator -reservedKeys $reservedKeys

    foreach ($key in @($keys)) {
        $found = $completions.GetEnumerator() | ? { $_.key -eq $key }
        if ($found) {
            $results += $found
        }
    }

    if (!$results) {
        $completions = Get-CompletionList $map -flatten:$flatten -leafsOnly:$leafsOnly -separator:$separator -reservedKeys $reservedKeys
        Write-Verbose "entry '$keys' not found in ($($completions.Keys))"
    }

    return $results
}

function Get-MapEntry(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -or $_ -is [array]
        })]
    $map,
    $key,
    $separator = "."
) {
    return (Get-MapEntries $map $key -separator $separator).Value
}

# TODO: key should be a hidden property of $entry
function Get-EntryCommand(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -or $_ -is [array] -or $_ -is [scriptblock]
        })]
    $entry,
    $commandKey = "exec"
) {
    if (!$entry) { throw "entry is NULL" }
    if ($entry -is [scriptblock]) { return $entry }

    if ($entry -is [System.Collections.IDictionary] -or $entry -is [System.Collections.Hashtable]) {
        if (!$entry.$commandKey) {
            throw "Command '$commandKey' not found"
            return $null
        }
        return $entry.$commandKey
    }

    throw "Entry of type $($entry.GetType().Name) is not supported"
    return $null
}
