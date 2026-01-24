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

function Test-IsParentEntry {
    <#
    .SYNOPSIS
        Determines if an entry is a parent container (has nested commands) or a leaf (executable command)
    .PARAMETER Entry
        The map entry to test
    .PARAMETER ListKey
        The key used to identify nested lists (default: "list")
    .PARAMETER ReservedKeys
        Array of reserved keys that should be skipped during processing
    .OUTPUTS
        [PSCustomObject] with IsParent (bool) and HasExplicitList (bool) properties
    #>
    param(
        $Entry,
        $ListKey = "list",
        $ReservedKeys = @("options", "exec", "list")
    )

    # If entry is not a hashtable, it's a leaf (scriptblock or other)
    if ($Entry -isnot [System.Collections.IDictionary]) {
        return [PSCustomObject]@{
            IsParent        = $false
            HasExplicitList = $false
        }
    }

    # Check for explicit list key (traditional nested structure)
    if ($Entry.$ListKey) {
        return [PSCustomObject]@{
            IsParent        = $true
            HasExplicitList = $true
        }
    }

    # Check if entry contains nested commands (hashtables or scriptblocks)
    $hasNestedCommands = $false
    foreach ($subKvp in $Entry.GetEnumerator()) {
        if ($subKvp.Key -in $reservedKeys -or $subKvp.Key -eq $ListKey) {
            continue
        }
        if ($subKvp.Value -is [System.Collections.IDictionary] -or $subKvp.Value -is [scriptblock]) {
            $hasNestedCommands = $true
            break
        }
    }

    return [PSCustomObject]@{
        IsParent        = $hasNestedCommands
        HasExplicitList = $false
    }
}
