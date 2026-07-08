function Test-ConcurrentlyEnabled {
    Write-Verbose "Checking concurrently plugin toggle from QCONF_CONCURRENTLY='$($env:QCONF_CONCURRENTLY)'"
    switch ($env:QCONF_CONCURRENTLY) {
        { $_ -in '0', 'false', 'no', 'off' } {
            Write-Verbose "Concurrently plugin disabled by environment toggle."
            return $false
        }
        default {
            Write-Verbose "Concurrently plugin enabled."
            return $true
        }
    }
}

function Test-VirtualBuildAllExpansion {
    param($Context)

    $isExpansion = $Context.Entry -match '\.all$' -and @($Context.Targets).Count -gt 1
    Write-Verbose "Virtual .all expansion check for entry '$($Context.Entry)': $isExpansion"
    return $isExpansion
}

function Format-QBuildCommand {
    param(
        [string]$mainCommand,
        [string]$Entry,
        [hashtable]$BoundParameters,
        [string[]]$RemainingArguments
    )

    Write-Verbose "Formatting qbuild command for entry '$Entry'"
    $parts = @($mainCommand)

    if ($BoundParameters.map -is [string]) {
        $parts += '-map'
        $parts += "'$($BoundParameters.map -replace "'", "''")'"
        Write-Verbose "Included map argument: $($BoundParameters.map)"
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
        Write-Verbose "Included passthrough arguments: $($passthrough -join ' ')"
    }

    $commandLine = $parts -join ' '
    Write-Verbose "Formatted qbuild command: $commandLine"
    return $commandLine
}

function Invoke-ConcurrentlyQBuild {
    param(
        [string[]]$Commands,
        [string[]]$Names
    )

    Write-Verbose "Invoking concurrently for $($Commands.Count) command(s)."
    if ($null -ne $script:ConfigMapConcurrentlyInvoker) {
        Write-Verbose "Using custom concurrently invoker script hook."
        & $script:ConfigMapConcurrentlyInvoker -Commands $Commands -Names $Names
        return
    }

    $a = @('--yes', 'concurrently')
    $a += @("--shell", "pwsh", "--color")
    if ($Names.Count -gt 0) {
        $a += '-n'
        $a += ($Names -join ',')
        Write-Verbose "Using concurrently task names: $($Names -join ', ')"
    }
    foreach ($command in $Commands) {
        Write-Verbose "Adding command: $command"
        $a += $command
    }
    
    Write-Verbose "Running: npx $($a -join ' ')"
    & npx @a | out-host
    if ($LASTEXITCODE -ne 0) {
        throw "concurrently exited with code $LASTEXITCODE"
    }
    Write-Verbose "concurrently finished successfully."
}
