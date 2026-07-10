function Invoke-TmuxDisplayMessage {
    param([string]$Format)

    try {
        $output = & tmux display-message -p $Format 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        return $output
    }
    catch {
        return $null
    }
}

function Test-InsideTmux {
    return [bool]$env:TMUX
}

function Get-TmuxInfo {
    if (-not (Test-InsideTmux)) {
        return $null
    }

    $sessionName = Invoke-TmuxDisplayMessage -Format '#{session_name}'
    $windowName = Invoke-TmuxDisplayMessage -Format '#{window_name}'

    [pscustomobject]@{
        sessionName = if ($null -eq $sessionName) { '' } else { $sessionName.Trim() }
        windowName  = if ($null -eq $windowName) { '' } else { $windowName.Trim() }
    }
}

function Test-TmuxSession {
    param([string]$SessionName)

    & tmux has-session -t $SessionName 2>$null
    return $LASTEXITCODE -eq 0
}

function Test-TmuxWindow {
    param(
        [string]$SessionName,
        [string]$WindowName
    )

    $windows = & tmux list-windows -t $SessionName -F '#{window_name}' 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return ($windows | ForEach-Object { $_.Trim() }) -contains $WindowName
}

function New-TmuxSession {
    param(
        [string]$SessionName,
        [string]$WindowName
    )

    & tmux new-session -d -s $SessionName -n $WindowName 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "tmux new-session failed"
    }
}

function New-TmuxWindow {
    param(
        [string]$SessionName,
        [string]$WindowName
    )

    & tmux new-window -t $SessionName -n $WindowName 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "tmux new-window failed"
    }
}

function Invoke-TmuxSendKeys {
    param(
        [string]$Target,
        [string[]]$Keys
    )

    & tmux send-keys -t $Target @Keys 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "tmux send-keys failed"
    }
}

function Invoke-TmuxCommand {
    param(
        [string]$Session,
        [string]$Window,
        [string]$Command,
        [string]$WorkingDirectory
    )

    if (-not (Test-TmuxSession -SessionName $Session)) {
        New-TmuxSession -SessionName $Session -WindowName $Window
    }
    elseif (-not (Test-TmuxWindow -SessionName $Session -WindowName $Window)) {
        New-TmuxWindow -SessionName $Session -WindowName $Window
    }

    $keys = @()
    if ($WorkingDirectory) {
        $resolvedDir = [System.IO.Path]::GetFullPath($WorkingDirectory)
        $escapedDir = $resolvedDir -replace "'", "''"
        $keys += "cd '$escapedDir'"
        $keys += 'Enter'
    }
    $keys += $Command
    $keys += 'Enter'

    $target = "$Session`:$Window"
    Invoke-TmuxSendKeys -Target $target -Keys $keys
}

function Format-TmuxCommand {
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

function Test-TmuxAutoWindowEnabled {
    switch ($env:QCONF_TMUX_AUTOWINDOW) {
        { $_ -in '0', 'false', 'no', 'off' } { return $false }
        default { return $true }
    }
}

function Test-TmuxBatchDispatchEnabled {
    param($Context)

    if (-not (Test-TmuxAutoWindowEnabled)) {
        return $false
    }

    $hasMap = $Context.Bound.map -and $Context.Bound.map -isnot [string]
    if ($hasMap) {
        return $false
    }

    $isExpansion = $Context.Entry -match '\.all$' -and @($Context.Targets).Count -gt 1
    if (-not $isExpansion) {
        return $false
    }

    return $null -ne (Get-TmuxInfo)
}
