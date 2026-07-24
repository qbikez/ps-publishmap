function Test-ConcurrentlyEnabled {
    $toggle = Get-ConfigMapSetting -Name Concurrently
    Write-Verbose "[concurrently] Checking plugin toggle from QCONF_Concurrently='$toggle'"
    $enabled = Test-ConfigMapFeatureEnabled -Name Concurrently
    if ($enabled) {
        Write-Verbose "[concurrently] Plugin enabled."
    }
    else {
        Write-Verbose "[concurrently] Plugin disabled by environment toggle."
    }
    return $enabled
}

function Test-ConcurrentlyPackageAvailable {
    & npx --no-install --loglevel error concurrently --version 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Test-ConcurrentlyAvailable {
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-Verbose "[concurrently] npx is not available on PATH."
        return $false
    }

    if (-not (Test-ConcurrentlyPackageAvailable)) {
        Write-Verbose "[concurrently] concurrently package is not available to npx."
        return $false
    }

    Write-Verbose "[concurrently] npx and concurrently are available."
    return $true
}

function Test-VirtualBuildAllExpansion {
    param($Context)

    $isExpansion = $Context.Entry -match '\.all$' -and @($Context.Targets).Count -gt 1
    Write-Verbose "[concurrently] Virtual .all expansion check for entry '$($Context.Entry)': $isExpansion"
    return $isExpansion
}

function Format-QBuildCommand {
    param(
        [string]$mainCommand,
        [string]$Entry,
        [hashtable]$BoundParameters,
        [string[]]$RemainingArguments
    )

    Write-Verbose "[concurrently] Formatting qbuild command for entry '$Entry'"
    $parts = @($mainCommand)

    if ($BoundParameters.map -is [string]) {
        $parts += '-map'
        $parts += "'$($BoundParameters.map -replace "'", "''")'"
        Write-Verbose "[concurrently] Included map argument: $($BoundParameters.map)"
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
        Write-Verbose "[concurrently] Included passthrough arguments: $($passthrough -join ' ')"
    }

    $commandLine = $parts -join ' '
    Write-Verbose "[concurrently] Formatted qbuild command: $commandLine"
    return $commandLine
}

function Invoke-Concurrently {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Commands
    )

    Write-Verbose "[concurrently] Invoking concurrently for $($Commands.Count) command(s)."
    if ($null -ne $script:ConfigMapConcurrentlyInvoker) {
        Write-Verbose "[concurrently] Using custom concurrently invoker script hook."
        & $script:ConfigMapConcurrentlyInvoker -Commands $Commands
        return
    }

    $names = @($Commands.Keys)
    $a = @('--yes', 'concurrently')
    $a += @("--shell", "pwsh", "--color")
    if ($names.Count -gt 0) {
        $a += '-n'
        $a += ($names -join ',')
        Write-Verbose "[concurrently] Using concurrently task names: $($names -join ', ')"
    }
    foreach ($name in $names) {
        $command = $Commands[$name]
        Write-Verbose "[concurrently] Adding command: $command"
        $a += $command
    }

    Write-Verbose "[concurrently] Running: npx $($a -join ' ')"
    & npx @a | out-host
    if ($LASTEXITCODE -ne 0) {
        throw "concurrently exited with code $LASTEXITCODE"
    }
    Write-Verbose "[concurrently] concurrently finished successfully."
}
