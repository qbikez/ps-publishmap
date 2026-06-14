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
        $ListKey = 'list'
    )

    $reservedKeys = (Get-MapLanguage 'build').reservedKeys + @('options', 'exec', 'list')

    if (Test-BuildAllEntry $Entry) { return $false }
    if ($Entry -is [scriptblock]) { return $true }
    if ($Entry -is [System.Collections.IDictionary]) {
        if ((Test-IsParentEntry $Entry $ListKey -reservedKeys $reservedKeys).IsParent) {
            return $false
        }

        return $Entry.exec -is [scriptblock]
    }

    return $false
}

function Get-BuildAllChildren {
    param(
        [System.Collections.IDictionary]$ParentEntry,
        [string]$ParentKey = '',
        [string]$Separator = '.',
        [string]$ListKey = 'list'
    )

    $reservedKeys = (Get-MapLanguage 'build').reservedKeys
    $result = [ordered]@{}

    foreach ($kvp in $ParentEntry.GetEnumerator()) {
        if ($kvp.Key -in $reservedKeys -or $kvp.Key -eq $ListKey -or $kvp.Key -eq 'all') {
            continue
        }

        if (!(Test-IsInvokableBuildEntry $kvp.Value $ListKey)) {
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

            $children = Get-BuildAllChildren $parentEntry -ParentKey $parentKey -Separator $separator
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
