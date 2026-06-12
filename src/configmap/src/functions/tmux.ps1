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
