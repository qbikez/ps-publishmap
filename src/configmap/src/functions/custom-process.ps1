#requires -version 7.0

function Get-EntryProcess {
    param(
        $Entry,
        [string]$Default = 'qbuild'
    )

    if (
        $Entry -is [System.Collections.IDictionary] -and
        $Entry._settings -is [System.Collections.IDictionary] -and
        $Entry._settings.Contains('process') -and
        $Entry._settings.process
    ) {
        return [string]$Entry._settings.process
    }
    return $Default
}

function Resolve-ConfigMapProcessRoot {
    <#
    .SYNOPSIS
        Find the owning map entry for a path and its process name.
        Walks up dotted paths so bootstrap.prepare resolves to bootstrap.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        [Parameter(Mandatory = $true)]
        [string]$Entry,
        $OperationContext,
        [string]$DefaultProcess = 'qbuild'
    )

    $key = $Entry
    if ($key -match '^(.*)\.all$') {
        $key = $Matches[1]
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    $candidates.Add($key) | Out-Null
    $walk = $key
    while ($walk -match '\.') {
        $walk = $walk.Substring(0, $walk.LastIndexOf('.'))
        $candidates.Add($walk) | Out-Null
    }

    $lastKey = $Entry
    $lastResolved = $null

    foreach ($candidate in $candidates) {
        $resolved = Get-MapEntry $Map $candidate -language 'build' -OperationContext $OperationContext
        if ($null -eq $resolved) {
            continue
        }

        $lastKey = $candidate
        $lastResolved = $resolved

        $proc = Get-EntryProcess $resolved -Default ''
        if ($proc) {
            return [pscustomobject]@{
                EntryKey      = $candidate
                EntryValue    = $resolved
                Process       = $proc
                OriginalEntry = $Entry
            }
        }
    }

    return [pscustomobject]@{
        EntryKey      = $lastKey
        EntryValue    = $lastResolved
        Process       = $DefaultProcess
        OriginalEntry = $Entry
    }
}

function Resolve-MapPath {
    <#
    .SYNOPSIS
        Get the source file path for process CLI -map handoff.
    #>
    param(
        $Map
    )

    if ($Map -is [System.Collections.IDictionary] -and $Map._sourceFile) {
        return [string]$Map._sourceFile
    }
    return $null
}

function Resolve-ConfigMapProcessCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName
    )

    $cmd = Get-Command $ProcessName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Process command '$ProcessName' not found on PATH / session. Install or import it so '& $ProcessName' works."
    }
    if ($cmd.CommandType -eq 'Alias') {
        $cmd = $cmd.ResolvedCommand
    }
    return $cmd
}

function Invoke-ConfigMapProcessComplete {
    <#
    .SYNOPSIS
        Run '<process> !complete …'; return trimmed lines, or $null if unsupported/missing.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $true)]
        [string]$MapPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$CompleteArgs
    )

    try {
        $cmd = Resolve-ConfigMapProcessCommand -ProcessName $ProcessName
    }
    catch {
        return $null
    }

    $global:LASTEXITCODE = 0
    $output = & $cmd -map $MapPath '!complete' @CompleteArgs 2>$null
    if ($global:LASTEXITCODE -eq 2) {
        return $null
    }

    return @(
        @($output) |
            ForEach-Object { "$_".Trim() } |
            Where-Object { $_ }
    )
}

function New-ConfigMapOpaqueDynamicParam {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [type]$ParameterType = [switch]
    )

    $attribute = New-Object System.Management.Automation.ParameterAttribute
    $attributes = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
    $attributes.Add($attribute)
    return New-Object System.Management.Automation.RuntimeDefinedParameter($Name, $ParameterType, $attributes)
}

function ConvertTo-ConfigMapProcessSplat {
    <#
    .SYNOPSIS
        Build a hashtable splat for '& process @splat' (path-only -map + opaque bound params).

        Hashtable splat is required so -Force / -Follow bind as switches; a string[] argv
        splat passes '-Force' as a literal remaining argument.

        Run:    -Entry <path>          →  process -map <file> -entry <path> …
        Verb:   -Command list …        →  process -map <file> -command list …
        Both:   -Command !complete -Entry x → process !complete -entry x
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$MapPath,
        [string]$Command,
        [AllowEmptyString()]
        [string]$Entry,
        [hashtable]$BoundParameters,
        [string[]]$RemainingArguments,
        [string[]]$SkipKeys = @(
            'entry', 'command', 'map', 'RemainingArguments',
            'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
            'ErrorVariable', 'WarningVariable', 'InformationVariable',
            'OutVariable', 'OutBuffer', 'PipelineVariable', 'ProgressAction'
        )
    )

    $splat = @{
        map = $MapPath
    }

    if ($Command) {
        $splat['command'] = $Command
    }

    if ($PSBoundParameters.ContainsKey('Entry') -and $null -ne $Entry) {
        $splat['entry'] = $Entry
    }

    if ($BoundParameters) {
        foreach ($key in @($BoundParameters.Keys)) {
            if ($key -in $SkipKeys) { continue }
            if ($key -like '_*') { continue }

            $val = $BoundParameters[$key]
            if ($val -is [System.Management.Automation.SwitchParameter]) {
                if ($val.IsPresent) {
                    $splat[$key] = $true
                }
                continue
            }
            if ($val -is [bool]) {
                if ($val) {
                    $splat[$key] = $true
                }
                continue
            }

            $splat[$key] = $val
        }
    }

    $passthrough = @($RemainingArguments | Where-Object { $null -ne $_ })
    if ($passthrough.Count -gt 0) {
        $splat['RemainingArguments'] = $passthrough
    }

    return $splat
}

function Invoke-ConfigMapProcessCli {
    <#
    .SYNOPSIS
        Invoke a process command via the call operator with path-only -map handoff.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $true)]
        [hashtable]$Splat
    )

    $cmd = Resolve-ConfigMapProcessCommand -ProcessName $ProcessName
    $global:LASTEXITCODE = 0
    & $cmd @Splat
    return $global:LASTEXITCODE
}

function Get-ConfigMapProcessNamesInMap {
    <#
    .SYNOPSIS
        Distinct non-qbuild process names declared in top-level entry settings.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        $OperationContext
    )

    if (-not $OperationContext) {
        $OperationContext = New-ConfigMapOperationContext
    }

    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @($Map.Keys)) {
        if ([string]$key -like '_*') { continue }
        $resolved = Get-MapEntry $Map $key -language 'build' -OperationContext $OperationContext
        $proc = Get-EntryProcess $resolved -Default 'qbuild'
        if ($proc -and $proc -ne 'qbuild') {
            [void]$names.Add($proc)
        }
    }
    return @($names | Sort-Object)
}

function Get-ConfigMapProcessCompleteParams {
    <#
    .SYNOPSIS
        Discover opaque parameter names via '<process> !complete -params -entry …'.
        Returns $null when unsupported (exit 2 / missing command).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $true)]
        [string]$MapPath,
        [Parameter(Mandatory = $true)]
        [string]$Entry
    )

    return Invoke-ConfigMapProcessComplete -ProcessName $ProcessName -MapPath $MapPath -CompleteArgs @{
        Params = $true
        Entry  = $Entry
    }
}

function Get-ConfigMapProcessCompleteWord {
    <#
    .SYNOPSIS
        Entry/token completion via '<process> !complete -word <prefix> [-entry …]'.
        Returns $null when unsupported (exit 2 / missing command).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $true)]
        [string]$MapPath,
        [AllowEmptyString()]
        [string]$Word = '',
        [string]$Entry
    )

    $completeArgs = @{ Word = $Word }
    if ($Entry) {
        $completeArgs['Entry'] = $Entry
    }

    return Invoke-ConfigMapProcessComplete -ProcessName $ProcessName -MapPath $MapPath -CompleteArgs $completeArgs
}

function New-ConfigMapProcessDynamicParam {
    <#
    .SYNOPSIS
        Build dynparams from !complete -params names; type step params from the map when available.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $true)]
        [string]$MapPath,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Map,
        [Parameter(Mandatory = $true)]
        [string]$Entry,
        [switch]$Follow
    )

    $names = Get-ConfigMapProcessCompleteParams -ProcessName $ProcessName -MapPath $MapPath -Entry $Entry
    $typed = Get-ProcessDynamicParam -Map $Map -ProcessKey $Entry -Follow:$Follow

    if ($null -eq $names) {
        return $typed
    }

    $merged = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    foreach ($name in $names) {
        if ($merged.ContainsKey($name)) { continue }
        if ($typed -and $typed.ContainsKey($name)) {
            $merged.Add($name, $typed[$name])
        }
        else {
            $merged.Add($name, (New-ConfigMapOpaqueDynamicParam -Name $name -ParameterType ([switch])))
        }
    }
    return $merged
}
