function Get-CompletionList {
    <#
    .SYNOPSIS
        Gets a flattened or hierarchical list of commands from a configuration map
    .PARAMETER map
        The configuration map to process. Can be a dictionary, array, scriptblock or string
    .PARAMETER flatten
        If true, flattens hierarchical commands into a single level. If false, maintains hierarchy with separators
    .PARAMETER separator
        The separator to use between parent and child command names when not flattened
    .PARAMETER groupMarker
        The marker to append to parent command names when flattened
    .PARAMETER listKey
        The key used to identify nested command lists
    .PARAMETER reservedKeys
        Array of reserved keys that should be skipped during processing
    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] containing the processed command list
    #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [ValidateScript({
                # the function do not suppurt strings, but ValidateScript iterates over the array, so for string[] we'll get string items here.
                # see: https://github.com/PowerShell/PowerShell/issues/6185
                $_ -is [System.Collections.IDictionary] -or $_ -is [array] -or $_ -is [scriptblock] -or $_ -is [string]
            })]
        $map,
        [switch][bool]$flatten = $false,
        [switch][bool]$leafsOnly = $false,
        $separator = ".",
        $groupMarker = $null,
        $listKey = "list",
        $reservedKeys = $null,
        $maxDepth = -1
    )

    if ($maxDepth -eq 0) {
        return @{}
    }

    if (!$groupMarker) {
        $groupMarker = $flatten ? "*" : ""
    }

    $list = $map.$listKey ? $map.$listKey : $map
    $list = $list -is [scriptblock] ? (Invoke-Command -ScriptBlock $list) : $list

    $r = switch ($true) {
        { $list -is [System.Collections.IDictionary] } {
            $result = [ordered]@{}

            foreach ($kvp in $list.GetEnumerator()) {
                if ($kvp.key -in $reservedKeys -or $kvp.key -eq $listKey) {
                    continue
                }
                $entry = $kvp.value
                $entryInfo = Test-IsParentEntry $entry $listKey -reservedKeys $reservedKeys

                if (!$entryInfo.IsParent) {
                    $result["$($kvp.key)"] = $entry
                    continue
                }

                # Add parent marker
                if (!$leafsOnly) {
                    $result["$($kvp.key)$groupMarker"] = $entry
                }

                # Get nested entries and add them with appropriate prefixes
                $subEntries = Get-CompletionList $entry -listKey $listKey -flatten:$flatten -leafsOnly:$leafsOnly -reservedKeys $reservedKeys -maxDepth ($maxDepth - 1)

                foreach ($sub in $subEntries.GetEnumerator()) {
                    $subKey = $flatten ? $sub.Key : "$($kvp.key)$separator$($sub.Key)"
                    $result[$subKey] = $sub.value
                }
            }

            return $result
        }
        { $list -is [array] } {
            $result = [ordered]@{}
            $subEntries = $list | ForEach-Object {
                $r = [ordered]@{}
            } {
                $r[$_] = $_
            } {
                $r
            }

            if ($subEntries) {
                foreach ($sub in $subEntries.GetEnumerator()) {
                    if ($sub.key -in $reservedKeys -or $sub.key -eq $listKey) {
                        continue
                    }
                    $result[$sub.key] = $sub.value
                }
            }
            return $result
        }
        { $list -is [string] } {
            throw "string type not supported"
        }
        default {
            throw "$($list.GetType().FullName) type not supported"
        }
    }

    return $r
}

function Get-EntryCompletion(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary]
        })]
    $map,
    [ValidateSet("build", "conf")]
    $language,
    $commandName,
    $parameterName,
    $wordToComplete,
    $commandAst,
    $fakeBoundParameters
) {
    # For hierarchical completion, we need both flattened and tree structures
    $flatList = Get-CompletionList $map -flatten:$true -reservedKeys $script:languages.$language.reservedKeys
    $treeList = Get-CompletionList $map -flatten:$false -reservedKeys $script:languages.$language.reservedKeys

    # Combine both lists and remove duplicates
    $allKeys = @($flatList.Keys) + @($treeList.Keys) | Sort-Object -Unique

    return $allKeys | ? { $_.startswith($wordToComplete) }
}
