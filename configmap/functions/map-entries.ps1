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

function Resolve-MapEntrySegments {
    param(
        [System.Collections.IDictionary]$Node,
        [string[]]$Segments,
        [string]$Separator,
        [hashtable]$IncludeCache,
        [hashtable]$LoadingIncludes
    )

    $notFound = [pscustomobject]@{ Found = $false; RequiresEnumeration = $false; Value = $null }
    if (!$Node -or !$Segments -or $Segments.Count -eq 0) {
        return $notFound
    }

    $list = if ($Node.list) { $Node.list } else { $Node }
    if ($list -is [scriptblock] -or $list -isnot [System.Collections.IDictionary]) {
        return [pscustomobject]@{ Found = $false; RequiresEnumeration = $true; Value = $null }
    }

    $remainingKey = $Segments -join $Separator
    if ($Segments.Count -gt 1 -and $list.Contains($remainingKey)) {
        return [pscustomobject]@{ Found = $false; RequiresEnumeration = $true; Value = $null }
    }

    $segment = $Segments[0]
    $rest = if ($Segments.Count -gt 1) { $Segments[1..($Segments.Count - 1)] } else { @() }
    $found = $false
    $value = $null

    foreach ($kvp in $list.GetEnumerator()) {
        if ($kvp.Key -eq '#include') {
            if ($kvp.Value -isnot [System.Collections.IDictionary]) {
                continue
            }

            foreach ($include in $kvp.Value.GetEnumerator()) {
                $usePrefix = $include.Value -is [System.Collections.IDictionary] -and $include.Value.prefix -eq $true
                if ($usePrefix -and $include.Key -ne $segment) {
                    continue
                }

                $includedMap = Import-IncludedConfigMap -DirectoryName "$($include.Key)" -BaseDir $Node._baseDir -Cache $IncludeCache -Loading $LoadingIncludes
                if (!$includedMap) {
                    continue
                }

                $includedSegments = if ($usePrefix) { $rest } else { $Segments }
                if ($includedSegments.Count -eq 0) {
                    continue
                }

                $includedResult = Resolve-MapEntrySegments -Node $includedMap -Segments $includedSegments -Separator $Separator -IncludeCache $IncludeCache -LoadingIncludes $LoadingIncludes
                if ($includedResult.RequiresEnumeration) {
                    return $includedResult
                }
                if ($includedResult.Found) {
                    $found = $true
                    $value = $includedResult.Value
                }
            }

            continue
        }

        if ($kvp.Key -ne $segment) {
            continue
        }

        if ($rest.Count -eq 0) {
            $found = $true
            $value = $kvp.Value
            continue
        }

        if ($kvp.Value -is [System.Collections.IDictionary]) {
            $childResult = Resolve-MapEntrySegments -Node $kvp.Value -Segments $rest -Separator $Separator -IncludeCache $IncludeCache -LoadingIncludes $LoadingIncludes
            if ($childResult.RequiresEnumeration) {
                return $childResult
            }
            if ($childResult.Found) {
                $found = $true
                $value = $childResult.Value
            }
        }
    }

    return [pscustomobject]@{ Found = $found; RequiresEnumeration = $false; Value = $value }
}

function Get-MapEntriesFromEntryList {
    param(
        $map,
        $keys,
        [switch][bool]$flatten = $false,
        [switch][bool]$leafsOnly = $false,
        $separator = ".",
        $language = $null
    )

    $results = @()
    $entries = Get-MapEntryList $map -flatten:$flatten -leafsOnly:$leafsOnly -separator:$separator -language $language

    foreach ($key in @($keys)) {
        $found = @($entries.GetEnumerator() | Where-Object { $_.Key -eq $key })
        if ($found.Count -eq 0) { continue }

        $target = $found[0]
        if ((Test-BuildAllEntry $target.Value) -and $language -eq 'build') {
            $parentKey = if ($key -match "^(.*)$([regex]::Escape($separator))all$") { $Matches[1] } else { '' }
            $parentEntry = if ($parentKey) {
                (Get-MapEntriesFromEntryList $map $parentKey -separator $separator -language $language).Value
            }
            else {
                $map
            }

            $children = Get-BuildAllChildren $parentEntry -Language $language -ParentKey $parentKey -Separator $separator
            foreach ($child in $children.GetEnumerator()) {
                $results += [System.Collections.DictionaryEntry]::new($child.Key, $child.Value)
            }
            continue
        }

        $results += $target
    }

    return $results
}

function Get-MapEntry(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -or $_ -is [array]
        })]
    $map,
    $key,
    $separator = ".",
    $language = $null,
    [hashtable]$OperationContext
) {
    return (Get-MapEntries $map $key -separator $separator -language $language -OperationContext $OperationContext).Value
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
    $language = $null,
    [hashtable]$OperationContext
) {
    $results = @()
    $useEnumeration = $flatten -or $leafsOnly -or $map -isnot [System.Collections.IDictionary]
    $includeCache = if ($OperationContext) { $OperationContext.IncludeCache } else { @{} }
    $loadingIncludes = if ($OperationContext) { $OperationContext.LoadingIncludes } else { @{} }

    foreach ($key in @($keys)) {
        if ($useEnumeration) {
            $results += Get-MapEntriesFromEntryList $map $key -flatten:$flatten -leafsOnly:$leafsOnly -separator $separator -language $language
            continue
        }

        $segments = $key -split [regex]::Escape($separator)
        $resolved = Resolve-MapEntrySegments -Node $map -Segments $segments -Separator $separator -IncludeCache $includeCache -LoadingIncludes $loadingIncludes
        if ($resolved.RequiresEnumeration) {
            $results += Get-MapEntriesFromEntryList $map $key -separator $separator -language $language
            continue
        }

        if ($resolved.Found) {
            $results += [System.Collections.DictionaryEntry]::new($key, $resolved.Value)
            continue
        }

        if ($language -eq 'build' -and $segments.Count -gt 1 -and $segments[-1] -eq 'all') {
            $parentKey = if ($key -match "^(.*)$([regex]::Escape($separator))all$") { $Matches[1] } else { '' }
            $parentEntry = if ($parentKey) {
                (Get-MapEntries $map $parentKey -separator $separator -language $language -OperationContext $OperationContext).Value
            }
            else {
                $map
            }

            if ($parentEntry -is [System.Collections.IDictionary] -and -not $parentEntry.Contains('all')) {
                $children = Get-BuildAllChildren $parentEntry -Language $language -ParentKey $parentKey -Separator $separator
                foreach ($child in $children.GetEnumerator()) {
                    $results += [System.Collections.DictionaryEntry]::new($child.Key, $child.Value)
                }
            }
        }
    }

    if (!$results) {
        Write-Verbose "entry '$keys' not found"
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
        [ValidateSet('build', 'conf')]
        $Language = 'build',
        $ReservedKeys
    )

    if (!$PSBoundParameters.ContainsKey('ReservedKeys')) {
        $ReservedKeys = (Get-MapLanguage $Language).reservedKeys
    }

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
