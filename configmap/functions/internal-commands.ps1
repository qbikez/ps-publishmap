function Get-ConfigMapInternalCommands {
    param(
        [ValidateSet('build')]
        [string]$Language = 'build',
        [AllowNull()]
        [System.Collections.IDictionary]$Map = $null
    )

    if ($Language -ne 'build') {
        return [ordered]@{}
    }

    return [ordered]@{
        'help'               = @{
            description = 'Show qbuild usage and internal commands'
            exec        = {
                param($_context)
                Write-InternalHelp -invocation $_context.Invocation
            }
        }
        'list'               = @{
            description = 'List available build commands'
            exec        = {
                param(
                    $_context,
                    [ValidateSet('@types')]
                    [string]$Type,
                    [switch]$Internal
                )

                Invoke-ConfigMapListCommand -Context $_context -Type $Type -Internal:$Internal
            }
            # Valid -Type values (CLI and canonical process names), resolved by ValidateSet('@types')
            types       = @(Get-ConfigMapListTypes -Map $Map -IncludeAliases)
            # list.<type> shorthands, one per process type in the map
            list        = New-ConfigMapListTypeEntries -Map $Map
        }
        '!init'              = @{
            description = 'Create a build map in the current directory'
            _internal   = @{
                completeWhen = 'localMapMissing'
            }
            exec        = {
                param($_context)

                if (Test-Path $_context.MapArgument) {
                    throw "map file '$($_context.MapArgument)' already exists"
                }
                Initialize-BuildMap -file $_context.MapArgument
            }
        }
        '!agent.init'        = @{
            description = 'Install ConfigMap agent skills'
            exec        = {
                param(
                    $_context,
                    [ValidateSet('user', 'project')]
                    [string]$Scope = 'project',
                    [ValidateSet('cursor', 'copilot', 'claude')]
                    [string]$Agent = 'cursor'
                )

                Initialize-QBuildAgent -Scope $Scope -Agent $Agent
            }
        }
        '!agent.skills'      = @{
            description = 'Print shipped agent skill markdown'
            exec        = {
                param(
                    $_context,
                    [string]$Name
                )

                $remaining = @($_context.RemainingArguments | Where-Object { $_ })
                if ($Name -and $remaining.Count -gt 0 -and $remaining[0] -eq $Name) {
                    $remaining = @($remaining | Select-Object -Skip 1)
                }
                if ($remaining.Count -gt 0) {
                    if ($Name -or $remaining.Count -gt 1) {
                        throw "!agent.skills accepts at most one skill name."
                    }
                    $Name = $remaining[0]
                }

                Show-QBuildAgentSkills -Name $Name
            }
        }
        '!extension.install' = @{
            description = 'Install the qbuild Map Tools VS Code extension'
            exec        = {
                param(
                    $_context,
                    [string]$Version,
                    [ValidateSet('code', 'cursor', 'code-insiders')]
                    [string]$Editor
                )

                Install-QBuildExtension -Version $Version -Editor $Editor
            }
        }
        '!settings'          = @{
            description = 'Show effective ConfigMap settings'
            exec        = {
                param(
                    $_context,
                    [string]$Path
                )

                $remaining = @($_context.RemainingArguments | Where-Object { $_ })
                if ($Path -and $remaining.Count -gt 0 -and $remaining[0] -eq $Path) {
                    $remaining = @($remaining | Select-Object -Skip 1)
                }
                if ($remaining.Count -gt 0) {
                    if ($Path -or $remaining.Count -gt 1) {
                        throw "!settings accepts at most one command path."
                    }
                    $Path = $remaining[0]
                }

                if (!$_context.UserMap) {
                    return Get-ConfigMapSettings
                }

                Get-ConfigMapSettingsForPath -Map $_context.UserMap -Path $Path
            }
        }
        '!describe'          = @{
            description = 'Describe commands in the build map'
            exec        = {
                param(
                    $_context,
                    [string]$Path
                )

                $remaining = @($_context.RemainingArguments | Where-Object { $_ })
                if ($Path -and $remaining.Count -gt 0 -and $remaining[0] -eq $Path) {
                    $remaining = @($remaining | Select-Object -Skip 1)
                }
                if ($remaining.Count -gt 0) {
                    if ($Path -or $remaining.Count -gt 1) {
                        throw "!describe accepts at most one command path."
                    }
                    $Path = $remaining[0]
                }

                if (!$_context.UserMap) {
                    throw "No build map file found. Run 'qbuild !init' to create one, or provide -map."
                }

                if ($Path) {
                    return Get-ConfigMapCommandCatalog -Map $_context.UserMap -Path $Path -Language build
                }
                Get-ConfigMapCommandCatalog -Map $_context.UserMap -Language build
            }
        }
        '!cache'             = @{
            description = 'Inspect or manage the discovery cache'
            exec        = {
                param($_context, [switch]$Porcelain)
                Invoke-QBuildCacheCommand -Context $_context -Action status -Porcelain:$Porcelain
            }
            list        = [ordered]@{
                status  = @{
                    description = 'Show discovery cache status'
                    exec        = {
                        param($_context, [switch]$Porcelain)
                        Invoke-QBuildCacheCommand -Context $_context -Action status -Porcelain:$Porcelain
                    }
                }
                clear   = @{
                    description = "Delete this map's discovery cache"
                    exec        = {
                        param($_context, [switch]$Porcelain)
                        Invoke-QBuildCacheCommand -Context $_context -Action clear -Porcelain:$Porcelain
                    }
                }
                rebuild = @{
                    description = "Clear and rebuild this map's discovery cache"
                    exec        = {
                        param($_context, [switch]$Porcelain)
                        Invoke-QBuildCacheCommand -Context $_context -Action rebuild -Porcelain:$Porcelain
                    }
                }
            }
        }
    }
}

function New-ConfigMapListTypeEntries {
    param([AllowNull()][System.Collections.IDictionary]$Map)

    $entries = [ordered]@{}
    foreach ($type in @(Get-ConfigMapListTypes -Map $Map)) {
        $entries[$type] = @{
            description = "List $type entries"
            # Create() keeps the block bound to module scope; GetNewClosure() would lose private functions.
            exec        = [scriptblock]::Create(
                "param(`$_context) Invoke-ConfigMapListCommand -Context `$_context -Type '$($type -replace "'", "''")'"
            )
        }
    }
    return $entries
}

function Invoke-ConfigMapListCommand {
    param($Context, [string]$Type, [switch]$Internal)

    if ($Internal) {
        if ($Type) {
            throw "list -Internal cannot be combined with -Type."
        }
        Write-InternalHelp -invocation $Context.Invocation -commands (Get-ConfigMapInternalCommandPaths -Map $Context.UserMap)
        return
    }

    if (!$Context.UserMap) {
        Write-Help -invocation $Context.Invocation -mapPath "./.build.map.ps1"
        return
    }

    Write-MapHelp -map $Context.UserMap -invocation $Context.Invocation -Type $Type
}

function Install-QBuildExtension {
    param(
        [string]$Version,
        [string]$Editor
    )

    $installer = Join-Path $PSScriptRoot '..\vscode-qbuild\install.ps1'
    if (!(Test-Path -LiteralPath $installer)) {
        throw "Extension installer not found at '$installer'. Run it from a ConfigMap checkout, or see vscode-qbuild/README.md for manual install."
    }

    . $installer
    Install-QBuildMapTools -Version $Version -Editor $Editor
}

function Get-ConfigMapAutoCommands {
    <#
    .SYNOPSIS
        Package-script proxy commands inferred from lockfiles next to the map (or the current directory).
        Bun wins over npm when both lockfiles exist.
    #>
    param(
        [AllowNull()]
        [System.Collections.IDictionary]$Map = $null
    )

    $baseDir = if ($Map -and $Map['_baseDir']) { [string]$Map['_baseDir'] } else { (Get-Location).Path }
    if (!(Test-Path -LiteralPath (Join-Path $baseDir 'package.json'))) {
        return [ordered]@{}
    }

    $manager = if ((Test-Path -LiteralPath (Join-Path $baseDir 'bun.lock')) -or (Test-Path -LiteralPath (Join-Path $baseDir 'bun.lockb'))) {
        'bun'
    }
    elseif (Test-Path -LiteralPath (Join-Path $baseDir 'package-lock.json')) {
        'npm'
    }
    else {
        return [ordered]@{}
    }

    return [ordered]@{
        $manager = @{
            description = "Run $manager scripts from package.json"
            _baseDir    = $baseDir
            _settings   = @{ process = $manager }
        }
    }
}

function Merge-ConfigMapCommands {
    param(
        [AllowNull()]
        [System.Collections.IDictionary]$Map,
        [ValidateSet('build')]
        [string]$Language = 'build'
    )

    $result = [ordered]@{}
    $commands = [ordered]@{}
    $internalCommands = Get-ConfigMapInternalCommands -Language $Language -Map $Map

    if ($Map) {
        foreach ($metadataKey in @('_baseDir', '_sourceFile', '_settings', '_dependsOn')) {
            if ($Map.Contains($metadataKey)) {
                $result[$metadataKey] = $Map[$metadataKey]
            }
        }
    }

    $userCommands = if ($Map -and $Map.Contains('list')) { $Map['list'] } else { $Map }

    # Auto-detected commands go first so a user-defined entry of the same name replaces them.
    foreach ($item in (Get-ConfigMapAutoCommands -Map $Map).GetEnumerator()) {
        $commands[$item.Key] = $item.Value
    }

    # Precedence policy: the last write wins. Reverse these two loops to let user commands override internals.
    if ($userCommands -is [System.Collections.IDictionary]) {
        foreach ($item in $userCommands.GetEnumerator()) {
            if ($item.Key -notin @('_baseDir', '_sourceFile', '_settings', '_dependsOn')) {
                $commands[$item.Key] = $item.Value
            }
        }
    }
    foreach ($item in $internalCommands.GetEnumerator()) {
        $commands[$item.Key] = $item.Value
    }

    $result['list'] = $commands
    return $result
}

function Test-ConfigMapCommandCompletion {
    param(
        [System.Collections.IDictionary]$Entry,
        [bool]$LocalMapExists
    )

    if (!$Entry -or !$Entry._internal -or !$Entry._internal.completeWhen) {
        return $true
    }

    switch ($Entry._internal.completeWhen) {
        'localMapMissing' { return !$LocalMapExists }
        default { return $true }
    }
}

function Test-ConfigMapInternalCommand {
    param(
        [string]$Name,
        [ValidateSet('build')]
        [string]$Language = 'build'
    )

    if (!$Name) {
        return $false
    }

    $commands = Get-ConfigMapInternalCommands -Language $Language
    # Nested internal entries (list.<type>) resolve through their parent command.
    return $commands.Contains($Name) -or $commands.Contains(($Name -split '\.')[0])
}

function Get-ConfigMapInternalCommandPaths {
    <#
    .SYNOPSIS
        Internal command names including nested entries (e.g. list.qconf, !cache.clear), for completion, help and list -Internal.
    #>
    param([AllowNull()][System.Collections.IDictionary]$Map)

    $paths = [ordered]@{}
    foreach ($item in (Get-ConfigMapAutoCommands -Map $Map).GetEnumerator()) {
        $paths[[string]$item.Key] = $item.Value
    }
    foreach ($item in (Get-ConfigMapInternalCommands -Language build -Map $Map).GetEnumerator()) {
        $paths[[string]$item.Key] = $item.Value
        if ($item.Value -is [System.Collections.IDictionary] -and $item.Value.list -is [System.Collections.IDictionary]) {
            foreach ($child in $item.Value.list.GetEnumerator()) {
                $paths["$($item.Key).$($child.Key)"] = $child.Value
            }
        }
    }
    return $paths
}
