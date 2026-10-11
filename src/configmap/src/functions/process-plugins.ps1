#requires -version 7.0

$script:ConfigMapProcesses = @{}

function Get-EntryProcess {
    param(
        $Entry,
        [string]$Default = 'qbuild'
    )

    if ($Entry -is [System.Collections.IDictionary] -and $Entry.Keys -contains 'process' -and $Entry.process) {
        return [string]$Entry.process
    }
    return $Default
}

function Get-ConfigMapProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Name -eq 'qbuild') {
        return $null
    }

    $process = $script:ConfigMapProcesses[$Name]
    if (-not $process) {
        throw "Unknown process '$Name'. Available: qbuild, $(($script:ConfigMapProcesses.Keys | Sort-Object) -join ', ')"
    }
    return $process
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

        if ($resolved -is [System.Collections.IDictionary] -and $resolved.Keys -contains 'process' -and $resolved.process) {
            return [pscustomobject]@{
                EntryKey      = $candidate
                EntryValue    = $resolved
                Process       = [string]$resolved.process
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

function Invoke-ConfigMapProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [Parameter(Mandatory = $true)]
        [string]$Member,
        [hashtable]$Context
    )

    $process = Get-ConfigMapProcess -Name $ProcessName
    if (-not $process) {
        return @{ Handled = $false }
    }

    $handler = $process[$Member]
    if (-not $handler) {
        return @{ Handled = $false }
    }

    $result = & $handler $Context
    if ($result -is [System.Management.Automation.RuntimeDefinedParameterDictionary]) {
        return $result
    }
    if ($result -is [hashtable] -and $result.ContainsKey('Handled')) {
        return $result
    }
    if ($null -eq $result) {
        return @{ Handled = $true }
    }
    return @{ Handled = $true; Result = $result }
}

function Resolve-ConfigMapProcessMapPath {
    <#
    .SYNOPSIS
        Resolve a filesystem path for process CLI -map handoff (path-only contract).
    #>
    param(
        $Map,
        $MapPath
    )

    if ($Map -is [System.Collections.IDictionary] -and $Map._sourceFile) {
        return [string]$Map._sourceFile
    }

    if ($MapPath -is [string] -and $MapPath) {
        if (Test-Path -LiteralPath $MapPath) {
            return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $MapPath).Path)
        }
        return [System.IO.Path]::GetFullPath($MapPath)
    }

    throw "Process delegation requires a map file path (-map <file>). In-memory maps are not supported."
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
    return $cmd
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
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$MapPath,
        [Parameter(Mandatory = $true)]
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
        map   = $MapPath
        entry = $Entry
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
    if ($cmd.CommandType -eq 'Alias') {
        $cmd = $cmd.ResolvedCommand
    }

    $global:LASTEXITCODE = 0
    & $cmd @Splat
    return $global:LASTEXITCODE
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

    try {
        $cmd = Resolve-ConfigMapProcessCommand -ProcessName $ProcessName
        if ($cmd.CommandType -eq 'Alias') {
            $cmd = $cmd.ResolvedCommand
        }
    }
    catch {
        return $null
    }

    $global:LASTEXITCODE = 0
    $output = & $cmd -map $MapPath '!complete' -Params -RemainingArguments @('-entry', $Entry) 2>$null
    if ($global:LASTEXITCODE -eq 2) {
        return $null
    }

    return @(
        @($output) |
            ForEach-Object { "$_".Trim() } |
            Where-Object { $_ }
    )
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
        # Process does not support !complete — fall back to map-derived step params only
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
