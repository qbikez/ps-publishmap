function New-BuildAllEntry {
    return [ordered]@{ __buildAll = $true }
}

function Test-BuildAllEntry {
    param($Entry)

    return $Entry -is [System.Collections.IDictionary] -and $Entry.__buildAll
}

function Test-IsInvokableBuildEntry {
    param(
        $Entry,
        [ValidateSet('build', 'conf')]$Language
    )

    $reservedKeys = (Get-MapLanguage $Language).reservedKeys

    if (Test-BuildAllEntry $Entry) { return $false }
    if ($Entry -is [scriptblock]) { return $true }
    if ($Entry -is [System.Collections.IDictionary]) {
        if (Test-IsParentEntry $Entry -reservedKeys $reservedKeys) {
            return $false
        }

        return $Entry.exec -is [scriptblock]
    }

    return $false
}

function Get-BuildAllChildren {
    param(
        [System.Collections.IDictionary]$ParentEntry,
        [ValidateSet('build', 'conf')]$Language,
        [string]$ParentKey = '',
        [string]$Separator = '.'
    )

    $reservedKeys = (Get-MapLanguage $Language).reservedKeys
    $result = [ordered]@{}

    foreach ($kvp in $ParentEntry.GetEnumerator()) {
        if ($kvp.Key -in $reservedKeys -or $kvp.Key -eq 'all') {
            continue
        }

        if (!(Test-IsInvokableBuildEntry $kvp.Value -Language $Language)) {
            continue
        }

        $childKey = if ($ParentKey) { "$ParentKey$Separator$($kvp.Key)" } else { $kvp.Key }
        $result[$childKey] = $kvp.Value
    }

    return $result
}

function Get-MapEntry(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -or $_ -is [array]
        })]
    $map,
    $key,
    $separator = ".",
    $language = $null
) {
    return (Get-MapEntries $map $key -separator $separator -language $language).Value
}

function Get-MapEntries(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -or $_ -is [array]
        })]
    $map,
    $keys,
    [switch][bool]$flatten = $false,
    [switch][bool]$leafsOnly = $false,
    $separator = ".",
    $language = $null
) {
    $results = @()

    $completions = Get-CompletionList $map -flatten:$flatten -leafsOnly:$leafsOnly -separator:$separator -language $language

    foreach ($key in @($keys)) {
        $found = @($completions.GetEnumerator() | Where-Object { $_.Key -eq $key })
        if ($found.Count -eq 0) { continue }

        $target = $found[0]
        if ((Test-BuildAllEntry $target.Value) -and $language -eq 'build') {
            $parentKey = if ($key -match '^(.*)\.all$') { $Matches[1] } else { '' }
            $parentEntry = if ($parentKey) {
                (Get-MapEntries $map $parentKey -separator $separator -language $language).Value
            }
            else {
                $map
            }

            $children = Get-BuildAllChildren $parentEntry -Language $language -ParentKey $parentKey -Separator $separator
            foreach ($child in $children.GetEnumerator()) {
                $results += [ordered]@{ Key = $child.Key; Value = $child.Value }
            }
            continue
        }

        $results += $target
    }

    if (!$results) {
        $completions = Get-CompletionList $map -flatten:$flatten -leafsOnly:$leafsOnly -separator:$separator -language $language
        Write-Verbose "entry '$keys' not found in ($($completions.Keys))"
    }

    return $results
}

# TODO: key should be a hidden property of $entry
function Get-EntryHasExec {
    param($Entry)

    if ($Entry -isnot [System.Collections.IDictionary]) { return $false }
    $exec = $Entry.exec
    if ($null -eq $exec) { return $false }
    if ($exec -is [array]) { return $exec.Count -gt 0 }
    return $true
}

function Get-EntryCommand(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -or $_ -is [array] -or $_ -is [scriptblock]
        })]
    [Parameter(Mandatory = $true)]
    $entry,
    [Parameter(Mandatory = $true)]
    $commandKey
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
    .PARAMETER ReservedKeys
        Array of reserved keys that should be skipped during processing
    .OUTPUTS
        [bool] $true if the entry is a parent container
    #>
    param(
        $Entry,
        $ReservedKeys = @("options", "exec", "list")
    )

    # If entry is not a hashtable, it's a leaf (scriptblock or other)
    if ($Entry -isnot [System.Collections.IDictionary]) {
        return $false
    }

    # Check for explicit list key (traditional nested structure)
    if ($Entry.list) {
        return $true
    }

    # Check if entry contains nested commands (hashtables or scriptblocks)
    foreach ($subKvp in $Entry.GetEnumerator()) {
        if ($subKvp.Key -in $reservedKeys) {
            continue
        }
        if ($subKvp.Value -is [System.Collections.IDictionary] -or $subKvp.Value -is [scriptblock]) {
            return $true
        }
    }

    return $false
}
