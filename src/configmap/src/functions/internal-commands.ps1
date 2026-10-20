function Get-ConfigMapInternalCommands {
    param(
        [ValidateSet('build')]
        [string]$Language = 'build'
    )

    if ($Language -ne 'build') {
        return [ordered]@{}
    }

    return [ordered]@{
        'help' = @{
            description = 'Show qbuild usage and internal commands'
            exec = {
                param($_context)
                Write-InternalHelp -invocation $_context.Invocation
            }
        }
        'list' = @{
            description = 'List available build commands'
            exec = {
                param(
                    $_context,
                    [string]$Type
                )

                if (!$_context.UserMap) {
                    Write-Help -invocation $_context.Invocation -mapPath "./.build.map.ps1"
                    return
                }

                Write-MapHelp -map $_context.UserMap -invocation $_context.Invocation -Type $Type
            }
        }
        '!init' = @{
            description = 'Create a build map in the current directory'
            _internal = @{
                completeWhen = 'localMapMissing'
            }
            exec = {
                param($_context)

                if (Test-Path $_context.MapArgument) {
                    throw "map file '$($_context.MapArgument)' already exists"
                }
                Initialize-BuildMap -file $_context.MapArgument
            }
        }
        '!agent.init' = @{
            description = 'Install ConfigMap agent skills'
            exec = {
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
        '!agent.skills' = @{
            description = 'Print shipped agent skill markdown'
            exec = {
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
            exec = {
                param(
                    $_context,
                    [string]$Version,
                    [ValidateSet('code', 'cursor', 'code-insiders')]
                    [string]$Editor
                )

                Install-QBuildExtension -Version $Version -Editor $Editor
            }
        }
        '!settings' = @{
            description = 'Show effective ConfigMap settings'
            exec = {
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
        '!describe' = @{
            description = 'Describe commands in the build map'
            exec = {
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
        '!cache' = @{
            description = 'Inspect or manage the discovery cache'
            exec = {
                param(
                    $_context,
                    [ValidateSet('status', 'clear', 'rebuild')]
                    [string]$Action = 'status'
                )

                $cacheAction = $Action
                $remaining = @($_context.RemainingArguments | Where-Object { $_ })
                if ($cacheAction -and $remaining.Count -gt 0 -and $remaining[0] -eq $cacheAction) {
                    $remaining = @($remaining | Select-Object -Skip 1)
                }
                if ($remaining.Count -gt 0) {
                    if ($PSBoundParameters.ContainsKey('Action') -or $remaining.Count -gt 1) {
                        throw "!cache accepts at most one action."
                    }
                    $cacheAction = $remaining[0]
                }
                if ($cacheAction -notin @('status', 'clear', 'rebuild')) {
                    throw "!cache accepts status, clear, or rebuild."
                }

                if (!$_context.UserMap) {
                    throw "No build map file found. Run 'qbuild !init' to create one, or provide -map."
                }

                Invoke-QBuildCacheCommand -Map $_context.UserMap -Language build -Action $cacheAction
            }
        }
    }
}

function Install-QBuildExtension {
    param(
        [string]$Version,
        [string]$Editor
    )

    $installer = Join-Path $PSScriptRoot '..\..\vscode-qbuild\install.ps1'
    if (!(Test-Path -LiteralPath $installer)) {
        throw "Extension installer not found at '$installer'. Run it from a ConfigMap checkout, or see vscode-qbuild/README.md for manual install."
    }

    . $installer
    Install-QBuildMapTools -Version $Version -Editor $Editor
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
    $internalCommands = Get-ConfigMapInternalCommands -Language $Language

    if ($Map) {
        foreach ($metadataKey in @('_baseDir', '_sourceFile', '_settings', '_dependsOn')) {
            if ($Map.Contains($metadataKey)) {
                $result[$metadataKey] = $Map[$metadataKey]
            }
        }
    }

    $userCommands = if ($Map -and $Map.Contains('list')) { $Map['list'] } else { $Map }

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

    return (Get-ConfigMapInternalCommands -Language $Language).Contains($Name)
}
