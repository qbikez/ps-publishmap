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
