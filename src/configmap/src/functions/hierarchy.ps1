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
