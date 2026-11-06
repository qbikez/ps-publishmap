#requires -version 7.0

# Run-once ledger for one top-level qbuild call; $null when no call is active.
$script:ConfigMapDependencyLedger = $null

function Test-ConfigMapEntryHasDependency {
    param($Entry)

    return $Entry -is [System.Collections.IDictionary] -and $Entry.Contains('_dependsOn') -and $null -ne $Entry['_dependsOn']
}

function Get-ConfigMapDependencyLabel {
    <#
    .SYNOPSIS
        _dependsOn items as written, for list and !describe: 'build' or 'build -Configuration:Release'.
    #>
    param($Entry)

    if (-not (Test-ConfigMapEntryHasDependency $Entry)) {
        return @()
    }

    $labels = foreach ($item in @($Entry['_dependsOn'])) {
        if ($item -is [System.Collections.IDictionary]) {
            $arguments = if ($item['args'] -is [System.Collections.IDictionary]) { $item['args'] } else { @{} }
            $argumentText = foreach ($name in ($arguments.Keys | Sort-Object)) { "-${name}:$($arguments[$name])" }
            (@([string]$item['entry']) + @($argumentText)) -join ' '
        }
        else {
            [string]$item
        }
    }
    return @($labels)
}

function ConvertTo-ConfigMapRunIdentity {
    <#
    .SYNOPSIS
        Key that decides whether two runs of an entry are the same run: entry path plus normalized arguments.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [System.Collections.IDictionary]$Arguments
    )

    if ($null -eq $Arguments -or $Arguments.Count -eq 0) {
        return $Key
    }

    $pairs = foreach ($name in ($Arguments.Keys | Sort-Object)) {
        $value = $Arguments[$name]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            $value = $value.IsPresent
        }
        if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
            $value = @($value) -join ','
        }
        "$name=$value"
    }
    return "$Key|$($pairs -join ';')"
}

function ConvertTo-ConfigMapDependencyRef {
    <#
    .SYNOPSIS
        Turns one _dependsOn item into @{ Key; Arguments; Identity } with Key resolved from the map root.
    #>
    param(
        $Item,
        [string]$DeclaringKey
    )

    $path = $null
    $arguments = @{}
    if ($Item -is [string]) {
        $path = $Item
    }
    elseif ($Item -is [System.Collections.IDictionary] -and $Item['entry'] -is [string]) {
        $path = $Item['entry']
        if ($null -ne $Item['args']) {
            if ($Item['args'] -isnot [System.Collections.IDictionary]) {
                throw "_dependsOn of '$DeclaringKey': args for '$path' must be a hashtable."
            }
            $arguments = $Item['args']
        }
    }

    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "_dependsOn of '$DeclaringKey': each item must be an entry path or @{ entry = '<path>'; args = @{ ... } }."
    }
    if ($path.StartsWith('../')) {
        throw "_dependsOn of '$DeclaringKey' uses '$path'; '../' is not supported. Use the full path from the map root."
    }

    $key = $path
    if ($path.StartsWith('./')) {
        $name = $path.Substring(2)
        $lastDot = $DeclaringKey.LastIndexOf('.')
        $key = if ($lastDot -ge 0) { "$($DeclaringKey.Substring(0, $lastDot)).$name" } else { $name }
    }

    return @{
        Path      = $path
        Key       = $key
        Arguments = $arguments
        Identity  = ConvertTo-ConfigMapRunIdentity -Key $key -Arguments $arguments
    }
}

function Test-ConfigMapExecGroupEntry {
    <#
    .SYNOPSIS
        True for a group of exec entries with no exec of its own: running it shows a chooser, not a task.
    #>
    param(
        [System.Collections.IDictionary]$Map,
        [string]$Key,
        $Entry,
        [hashtable]$OperationContext
    )

    if ($Entry -isnot [System.Collections.IDictionary] -or (Get-EntryHasExec $Entry)) {
        return $false
    }
    if (-not (Test-IsParentEntry $Entry -ReservedKeys (Get-MapLanguage build).reservedKeys)) {
        return $false
    }
    $settings = Get-ConfigMapSettingsForPath -Map $Map -Path $Key -OperationContext $OperationContext
    return $settings.Process -eq $script:ConfigMapDefaultProcessName
}

function Get-ConfigMapDependencySource {
    <#
    .SYNOPSIS
        Entries whose _dependsOn apply when Key runs: the entry itself, or for 'group.all' the group and each child.
    #>
    param(
        [System.Collections.IDictionary]$Map,
        [string]$Key,
        [hashtable]$OperationContext
    )

    if ($Key -match '^(.+)\.all$') {
        $groupKey = $Matches[1]
        $group = Get-MapEntry $Map $groupKey -language build -OperationContext $OperationContext
        if ($group -is [System.Collections.IDictionary]) {
            @{ Key = $groupKey; Entry = $group }
        }
        foreach ($child in @(Get-MapEntries $Map $Key -language build -OperationContext $OperationContext)) {
            @{ Key = [string]$child.Key; Entry = $child.Value }
        }
        return
    }

    $entry = Get-MapEntry $Map $Key -language build -OperationContext $OperationContext
    if ($null -eq $entry -or (Test-ConfigMapExecGroupEntry -Map $Map -Key $Key -Entry $entry -OperationContext $OperationContext)) {
        return
    }
    @{ Key = $Key; Entry = $entry }
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
    if ($Ref.Key -notmatch '\.all$' -and (Test-ConfigMapExecGroupEntry -Map $Map -Key $Ref.Key -Entry $targets[0].Value -OperationContext $OperationContext)) {
        throw "Dependency '$($Ref.Path)' of '$DependentKey' is a group with no exec. Depend on '$($Ref.Key).all' to run its children."
    }
}

function Add-ConfigMapDependencyPlanItem {
    param(
        [hashtable]$State,
        [string]$Key
    )

    foreach ($source in @(Get-ConfigMapDependencySource -Map $State.Map -Key $Key -OperationContext $State.OperationContext)) {
        if (-not (Test-ConfigMapEntryHasDependency $source.Entry)) {
            continue
        }

        foreach ($item in @($source.Entry['_dependsOn'])) {
            $ref = ConvertTo-ConfigMapDependencyRef -Item $item -DeclaringKey $source.Key
            if ($State.Stack.Contains($ref.Key)) {
                $chain = @($State.Stack.GetRange($State.Stack.IndexOf($ref.Key), $State.Stack.Count - $State.Stack.IndexOf($ref.Key))) + $ref.Key
                throw "Dependency cycle: $($chain -join ' -> ')"
            }
            if ($State.Completed.Contains($ref.Identity) -or $State.Planned.Contains($ref.Identity)) {
                continue
            }
            Assert-ConfigMapDependencyTarget -Map $State.Map -Ref $ref -DependentKey $source.Key -OperationContext $State.OperationContext

            $State.Stack.Add($ref.Key)
            Add-ConfigMapDependencyPlanItem -State $State -Key $ref.Key
            $State.Stack.RemoveAt($State.Stack.Count - 1)

            $null = $State.Planned.Add($ref.Identity)
            $State.Plan.Add(@{
                    Key          = $ref.Key
                    Arguments    = $ref.Arguments
                    Identity     = $ref.Identity
                    DependentKey = $source.Key
                })
        }
    }
}

function Resolve-ConfigMapDependencyPlan {
    <#
    .SYNOPSIS
        Ordered dependencies to run before EntryKey: depth-first, each identity once, skipping completed runs.
    .OUTPUTS
        List of @{ Key; Arguments; Identity; DependentKey }. Throws on cycles and unresolved items.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Map,
        [Parameter(Mandatory)]
        [string]$EntryKey,
        [System.Collections.Generic.HashSet[string]]$Completed = [System.Collections.Generic.HashSet[string]]::new(),
        [hashtable]$OperationContext
    )

    $state = @{
        Map              = $Map
        OperationContext = $OperationContext
        Completed        = $Completed
        Planned          = [System.Collections.Generic.HashSet[string]]::new()
        Stack            = [System.Collections.Generic.List[string]]::new()
        Plan             = [System.Collections.Generic.List[hashtable]]::new()
    }
    $state.Stack.Add($EntryKey)
    Add-ConfigMapDependencyPlanItem -State $state -Key $EntryKey
    return , $state.Plan
}

function New-ConfigMapDependencyLedger {
    return @{
        # Identities of every run in this qbuild call, requested or dependency.
        Completed       = [System.Collections.Generic.HashSet[string]]::new()
        # Identities that ran as a dependency; a later request for one is skipped.
        RanAsDependency = [System.Collections.Generic.HashSet[string]]::new()
        # >0 while a dependency runs, so plugins keep it in this process instead of a tmux window.
        ActiveDepth     = 0
    }
}

function Test-ConfigMapDependencyRunActive {
    return $null -ne $script:ConfigMapDependencyLedger -and $script:ConfigMapDependencyLedger.ActiveDepth -gt 0
}

function Get-QBuildRequestArgument {
    <#
    .SYNOPSIS
        Arguments that make a requested qbuild entry a distinct run: entry parameters, process action/value and passthrough.
    #>
    param([System.Collections.IDictionary]$BoundParameters)

    $hostKeys = @('entry', 'command', 'map', 'NoDeps') + [System.Management.Automation.PSCmdlet]::CommonParameters
    $arguments = @{}
    foreach ($name in $BoundParameters.Keys) {
        if ($name -notin $hostKeys) {
            $arguments[$name] = $BoundParameters[$name]
        }
    }
    return $arguments
}

function Invoke-ConfigMapDependencyPlan {
    <#
    .SYNOPSIS
        Runs each planned dependency as its own `qbuild <entry> -NoDeps`, so it reaches its own process handler.
    #>
    param(
        [System.Collections.Generic.List[hashtable]]$Plan,
        $MapArgument,
        [hashtable]$Ledger
    )

    foreach ($step in $Plan) {
        Write-Host "-> $($step.Key) (dependency of $($step.DependentKey))" -ForegroundColor Cyan
        $arguments = @{}
        foreach ($name in $step.Arguments.Keys) {
            $arguments[$name] = $step.Arguments[$name]
        }

        $global:LASTEXITCODE = 0
        $Ledger.ActiveDepth++
        try {
            Invoke-QBuild -map $MapArgument -entry $step.Key -NoDeps @arguments
        }
        finally {
            $Ledger.ActiveDepth--
        }
        if ($global:LASTEXITCODE) {
            throw "Dependency '$($step.Key)' of '$($step.DependentKey)' failed with exit code $global:LASTEXITCODE."
        }

        $null = $Ledger.Completed.Add($step.Identity)
        $null = $Ledger.RanAsDependency.Add($step.Identity)
    }
}
