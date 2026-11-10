#requires -version 7.0

function Test-ConfigMapEntryHasDependency {
    param($Entry)

    return $Entry -is [System.Collections.IDictionary] -and $Entry.Contains('_dependsOn') -and $null -ne $Entry['_dependsOn']
}

function ConvertTo-ConfigMapDependencyRef {
    <#
    .SYNOPSIS
        Turns one _dependsOn item into @{ Path; Key } with Key resolved from the map root.
    .DESCRIPTION
        './name' (or '.\name') is a sibling: it replaces the last segment of DeclaringKey.
        Any '..' segment is rejected, so every item resolves inside the map without walking up.
    #>
    param(
        $Item,
        [string]$DeclaringKey
    )

    if ($Item -isnot [string] -or [string]::IsNullOrWhiteSpace($Item)) {
        throw "_dependsOn of '$DeclaringKey': each item must be an entry path from the map root."
    }

    $path = $Item.Replace('\', '/')
    if ($path.Split('/') -contains '..') {
        throw "_dependsOn of '$DeclaringKey': '$Item' is not supported; use the full path from the map root or ./name for a sibling."
    }

    $key = $Item
    if ($path.StartsWith('./')) {
        $name = $path.Substring(2)
        $lastDot = $DeclaringKey.LastIndexOf('.')
        $key = if ($lastDot -lt 0) { $name } else { "$($DeclaringKey.Substring(0, $lastDot)).$name" }
    }

    return @{
        Path = $Item
        Key  = $key
    }
}

function Assert-ConfigMapDependencyTarget {
    param(
        [System.Collections.IDictionary]$Map,
        [hashtable]$Ref,
        [string]$DependentKey,
        [hashtable]$OperationContext
    )

    $targets = @(Get-MapEntries $Map $Ref.Key -language build -OperationContext $OperationContext)
    if ($targets.Count -eq 0) {
        throw "Dependency '$($Ref.Path)' of '$DependentKey' was not found. _dependsOn lists entries to run first; list files that invalidate the discovery cache in _cacheDependsOn."
    }
}

function Add-ConfigMapDependencyPlanItem {
    param(
        [hashtable]$State,
        [string]$Key
    )

    $entry = Get-MapEntry $State.Map $Key -language build -OperationContext $State.OperationContext
    if (-not (Test-ConfigMapEntryHasDependency $entry)) {
        return
    }

    foreach ($item in @($entry['_dependsOn'])) {
        $ref = ConvertTo-ConfigMapDependencyRef -Item $item -DeclaringKey $Key
        if ($State.Stack.Contains($ref.Key)) {
            $start = $State.Stack.IndexOf($ref.Key)
            $chain = @($State.Stack.GetRange($start, $State.Stack.Count - $start)) + $ref.Key
            throw "Dependency cycle: $($chain -join ' -> ')"
        }
        if ($State.Planned.Contains($ref.Key)) {
            continue
        }
        Assert-ConfigMapDependencyTarget -Map $State.Map -Ref $ref -DependentKey $Key -OperationContext $State.OperationContext

        $State.Stack.Add($ref.Key)
        Add-ConfigMapDependencyPlanItem -State $State -Key $ref.Key
        $State.Stack.RemoveAt($State.Stack.Count - 1)

        $null = $State.Planned.Add($ref.Key)
        $State.Plan.Add(@{
                Key          = $ref.Key
                DependentKey = $Key
            })
    }
}

function Resolve-ConfigMapDependencyPlan {
    <#
    .SYNOPSIS
        Ordered dependencies to run before EntryKey: depth-first, each one once.
    .OUTPUTS
        List of @{ Key; DependentKey }, without EntryKey itself. Throws on cycles and unresolved items.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Map,
        [Parameter(Mandatory)]
        [string]$EntryKey,
        [hashtable]$OperationContext
    )

    $plan = [System.Collections.Generic.List[hashtable]]::new()
    # Entries without _dependsOn are the common case; keep their cost to one lookup.
    $entry = Get-MapEntry $Map $EntryKey -language build -OperationContext $OperationContext
    if (-not (Test-ConfigMapEntryHasDependency $entry)) {
        return , $plan
    }

    $state = @{
        Map              = $Map
        OperationContext = $OperationContext
        Planned          = [System.Collections.Generic.HashSet[string]]::new()
        Stack            = [System.Collections.Generic.List[string]]::new()
        Plan             = $plan
    }
    $state.Stack.Add($EntryKey)
    Add-ConfigMapDependencyPlanItem -State $state -Key $EntryKey
    return , $plan
}

function Invoke-ConfigMapDependencyPlan {
    <#
    .SYNOPSIS
        Runs each planned dependency as its own `qbuild <entry> -NoDeps`, so it reaches its own process handler.
    #>
    param(
        [System.Collections.Generic.List[hashtable]]$Plan,
        $MapArgument
    )

    foreach ($step in $Plan) {
        Write-Host "-> $($step.Key) (dependency of $($step.DependentKey))" -ForegroundColor Cyan

        # A code left by earlier commands must not fail this dependency.
        $global:LASTEXITCODE = 0
        Invoke-QBuild -map $MapArgument -entry $step.Key -NoDeps
        if ($global:LASTEXITCODE) {
            throw "Dependency '$($step.Key)' of '$($step.DependentKey)' failed with exit code $global:LASTEXITCODE."
        }
    }
}
