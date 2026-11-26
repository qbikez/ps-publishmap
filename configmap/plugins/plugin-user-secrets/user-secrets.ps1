# Per-process cache of listed secrets, keyed by `id:<UserSecretsId>` or `project:<path>`.
# Each entry keeps a stamp of the store's secrets.json, so a write from anywhere (qconf set,
# `dotnet user-secrets set`) makes the next read list again.
$script:userSecretsCache = @{}

# Lists the secrets of a project (`--project $dir`) or, when $Id is given, of a UserSecretsId
# (`--id $Id`, no project needed). Check $LASTEXITCODE for a failed listing: it is 0 on success
# (also for a cached result), and the result is then an empty table.
function script:get-user-secrets($dir, [string]$Id) {
    if ($Id) {
        $cacheKey = "id:$Id"
        $storeId = $Id
        $target = @('--id', $Id)
    }
    else {
        $cacheKey = "project:$dir"
        $storeId = Get-ProjectUserSecretsId $dir
        # No --project means the project in the current directory, as dotnet does by default.
        $target = if ($dir) { @('--project', $dir) } else { @() }
    }

    # Without a known store path a change cannot be detected, so that listing is not cached.
    $stamp = Get-UserSecretsStamp $storeId
    $cached = $script:userSecretsCache[$cacheKey]
    if ($cached -and $null -ne $stamp -and $cached.Stamp -eq $stamp) {
        $global:LASTEXITCODE = 0
        return $cached.Secrets.Clone()
    }

    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        $global:LASTEXITCODE = 1
        return @{}
    }

    try {
        # Output is captured, never forwarded, so secret values cannot leak into warnings.
        $output = dotnet user-secrets list @target --json 2>$null
        if ($LASTEXITCODE -ne 0) { return @{} }

        $secrets = ConvertFrom-UserSecretsJson -Lines @($output | ForEach-Object { "$_" })
    }
    catch {
        # The exception text may quote the output, so it is not shown.
        Write-Warning "Failed to read user secrets ($(format-user-secrets-target $dir -Id $Id)): 'dotnet user-secrets list --json' printed output that is not JSON."
        $global:LASTEXITCODE = 1
        return @{}
    }

    if ($null -ne $stamp) {
        $script:userSecretsCache[$cacheKey] = @{ Stamp = $stamp; Secrets = $secrets.Clone() }
    }
    $global:LASTEXITCODE = 0
    return $secrets
}

# How to name the secrets store in a dotnet command: `--id x` or `-p dir`.
function script:format-user-secrets-target($dir, [string]$Id) {
    if ($Id) { return "--id $Id" }
    return "-p $dir"
}

function script:ConvertFrom-UserSecretsJson {
    <#
    .SYNOPSIS
        Parse `dotnet user-secrets list --json` output, which wraps the JSON in //BEGIN and //END lines.
    #>
    param([string[]]$Lines)

    $begin = [array]::IndexOf($Lines, '//BEGIN')
    $end = [array]::LastIndexOf($Lines, '//END')
    if ($begin -ge 0 -and $end -gt $begin) {
        $Lines = if ($end -gt $begin + 1) { $Lines[($begin + 1)..($end - 1)] } else { @() }
    }
    $json = ($Lines | Where-Object { $_ -notmatch '^\s*//(BEGIN|END)\s*$' }) -join "`n"

    # Configuration keys are case-insensitive, like a default PowerShell hashtable.
    $secrets = @{}
    if ([string]::IsNullOrWhiteSpace($json)) { return $secrets }

    $parsed = $json | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    foreach ($key in $parsed.Keys) { $secrets[$key] = $parsed[$key] }
    return $secrets
}

function script:Get-UserSecretsStorePath([string]$Id) {
    # Where `dotnet user-secrets` keeps the store of an id (Microsoft.Extensions.Configuration.UserSecrets).
    $root = if ($IsWindows) { Join-Path $env:APPDATA 'Microsoft/UserSecrets' } else { Join-Path $HOME '.microsoft/usersecrets' }
    return Join-Path $root $Id 'secrets.json'
}

function script:Get-ProjectUserSecretsId([string]$Project) {
    <#
    .SYNOPSIS
        The UserSecretsId declared in a project file (or the one project file in a directory); $null when not found.
    #>
    if (-not $Project) { $Project = (Get-Location).Path }

    $file = $Project
    if (Test-Path -LiteralPath $Project -PathType Container) {
        $files = @(Get-ChildItem -LiteralPath $Project -File -Filter '*.*proj' -ErrorAction SilentlyContinue)
        if ($files.Count -ne 1) { return $null }
        $file = $files[0].FullName
    }
    elseif (-not (Test-Path -LiteralPath $Project -PathType Leaf)) {
        return $null
    }

    $match = [regex]::Match((Get-Content -LiteralPath $file -Raw), '<UserSecretsId>\s*([^<\s]+)\s*</UserSecretsId>')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function script:Get-UserSecretsStamp([string]$Id) {
    if (-not $Id) { return $null }
    $store = Get-Item -LiteralPath (Get-UserSecretsStorePath $Id) -ErrorAction SilentlyContinue
    if (-not $store) { return 'missing' }
    return "$($store.LastWriteTimeUtc.Ticks)/$($store.Length)"
}

function script:Clear-UserSecretsCache {
    $script:userSecretsCache = @{}
}
