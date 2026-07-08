function Format-QBuildCommand {
    param(
        [string]$Entry,
        [hashtable]$BoundParameters,
        [string[]]$RemainingArguments
    )

    $parts = @('qbuild')

    if ($BoundParameters.map -is [string]) {
        $parts += '-map'
        $parts += "'$($BoundParameters.map -replace "'", "''")'"
    }

    $parts += $Entry

    $skip = @(
        'entry', 'map', 'command', 'RemainingArguments',
        'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
        'OutVariable', 'OutBuffer', 'PipelineVariable'
    )

    foreach ($key in ($BoundParameters.Keys | Sort-Object)) {
        if ($key -in $skip) { continue }

        $val = $BoundParameters[$key]
        if ($val -is [switch]) {
            if ($val.IsPresent) { $parts += "-$key" }
        }
        elseif ($val -is [bool]) {
            if ($val) { $parts += "-$key" }
        }
        else {
            $parts += "-$key"
            $parts += "'$($val.ToString() -replace "'", "''")'"
        }
    }

    $passthrough = @($RemainingArguments) | Where-Object { $null -ne $_ }
    if ($passthrough.Count -gt 0) {
        $parts += '--'
        $parts += $passthrough
    }

    return $parts -join ' '
}

function Test-QBuildTmuxAutoWindowEnabled {
    switch ($env:QCONF_TMUX_AUTOWINDOW) {
        { $_ -in '0', 'false', 'no', 'off' } { return $false }
        default { return $true }
    }
}

function Test-QBuildCanDelegateToTmux {
    param([hashtable]$Bound)

    if ($Bound.map -and $Bound.map -isnot [string]) {
        return $false
    }

    return $true
}

function Invoke-QBuildTarget {
    param(
        [string]$TargetKey,
        $TargetEntry,
        [string]$Command,
        [hashtable]$Bound,
        [string[]]$RemainingArguments
    )

    if (Test-QBuildTmuxAutoWindowEnabled -and Test-InsideTmux -and (Test-QBuildCanDelegateToTmux -Bound $Bound)) {
        $tmuxInfo = Get-TmuxInfo
        $shouldDelegate = $null -ne $tmuxInfo -and $tmuxInfo.windowName -ne $TargetKey
        
        if ($shouldDelegate) {    
            $qbuildCommand = Format-QBuildCommand -Entry $TargetKey -BoundParameters $Bound -RemainingArguments $RemainingArguments
            Invoke-TmuxCommand -Session $tmuxInfo.sessionName -Window $TargetKey -Command $qbuildCommand -WorkingDirectory (Get-Location).Path
            return
        }
    }

    Invoke-EntryCommand -entry $TargetEntry -key $Command -bound $Bound
}
