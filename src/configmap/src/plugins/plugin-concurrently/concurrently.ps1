function Test-ConcurrentlyEnabled {
    switch ($env:QCONF_CONCURRENTLY) {
        { $_ -in '0', 'false', 'no', 'off' } { return $false }
        default { return $true }
    }
}

function Test-VirtualBuildAllExpansion {
    param($Context)

    return $Context.Entry -match '\.all$' -and @($Context.Targets).Count -gt 1
}

function Format-QBuildCommand {
    param(
        [string]$mainCommand,
        [string]$Entry,
        [hashtable]$BoundParameters,
        [string[]]$RemainingArguments
    )

    $parts = @($mainCommand)

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

function Invoke-ConcurrentlyQBuild {
    param(
        [string[]]$Commands,
        [string[]]$Names
    )

    if ($null -ne $script:ConfigMapConcurrentlyInvoker) {
        & $script:ConfigMapConcurrentlyInvoker -Commands $Commands -Names $Names
        return
    }

    $args = @('--yes', 'concurrently')
    if ($Names.Count -gt 0) {
        $args += '-n'
        $args += ($Names -join ',')
    }
    $args += $Commands

    & npx @args
    if ($LASTEXITCODE -ne 0) {
        throw "concurrently exited with code $LASTEXITCODE"
    }
}
