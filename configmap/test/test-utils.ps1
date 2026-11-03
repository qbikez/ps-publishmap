# Shared test helpers for ConfigMap tests

function Should-MatchObject ($ActualValue, [hashtable]$ExpectedValue, [switch] $Negate, [string] $Because) {
    <#
    .SYNOPSIS
        Asserts if hashtable/objects contains the same keys and values
    .EXAMPLE
        @{ a = 1 } | Should -MatchObject @{ a = 1 }

        Checks if object matches the other one. This will pass.

    .EXAMPLE
        @{ a = 1, b = 2 } | Should -MatchObject @{ a = 1 }

        Checks if object matches the other one. Additional keys on the actual value are ignored.
    #>

    $diff = [ordered]@{}
    foreach ($kvp in $ExpectedValue.GetEnumerator()) {
        $key = $kvp.Key
        $actual = $ActualValue.$key
        $expected = $kvp.Value
        if ($actual -ne $expected) {
            $diff["-$key"] = $expected
            $diff["+$key"] = $actual
        }
    }

    if ($Negate) {
        if ($diff.Count -gt 0) {
            return [pscustomobject]@{
                Succeeded      = $true
                FailureMessage = $null
            }
        }
        else {
            return [pscustomobject]@{
                Succeeded      = $false
                FailureMessage = "Expected object to not match $($actual | ConvertTo-Json). $Because"
            }
        }
    }
    else {
        if ($diff.Count -eq 0) {
            return [pscustomobject]@{
                Succeeded      = $true
                FailureMessage = $null
            }
        }
        else {
            return [pscustomobject]@{
                Succeeded      = $false
                FailureMessage = "Expected objects to match. Diff: $($diff | ConvertTo-Json). $Because"
            }
        }
    }
}

# Initialize the MatchObject Pester operator
Add-ShouldOperator -Name MatchObject `
    -InternalName 'Should-MatchObject' `
    -Test ${function:Should-MatchObject} `
    -SupportsArrayInput