function Get-RelativeMapDisplayPath {
    param($Map)

    $mapPath = Resolve-MapPath -Map $Map
    if (-not $mapPath) {
        return $null
    }

    $full = [System.IO.Path]::GetFullPath($mapPath)
    $cwd = [System.IO.Path]::GetFullPath((Get-Location).Path)
    $relative = [System.IO.Path]::GetRelativePath($cwd, $full)
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative -eq '.') {
        $relative = [System.IO.Path]::GetFileName($full)
    }
    $relative = $relative -replace '\\', '/'
    if ($relative -notmatch '^\.\.?/' -and $relative -notmatch '^[A-Za-z]:' -and $relative -notmatch '^/') {
        $relative = "./$relative"
    }
    return $relative
}

function Write-CommandHelpLine {
    param($name, $description, $paramInfo, $maxNameLength)
    $paddedName = $name.PadRight($maxNameLength)
    Write-Host "    " -NoNewline
    Write-Host "$paddedName" -ForegroundColor Green -NoNewline
    if ($paramInfo) {
        Write-Host " [$paramInfo]" -ForegroundColor DarkGray -NoNewline
    }
    Write-Host "  $description" -ForegroundColor White
}

function Get-CommandHelpParamInfo {
    param($script)

    try {
        $entry = Get-EntryCommand $script "exec"
    }
    catch {
        $entry = $null
    }
    if ($entry -isnot [scriptblock]) {
        return ''
    }

    $args = Get-ScriptArgs $entry
    return (($args.Keys | ForEach-Object { "-$_" }) -join " ")
}

function Get-ConfigMapModuleVersion {
    $module = (Get-Command Invoke-QBuild -ErrorAction Stop).Module
    if ($module.Version -and $module.Version -ne [version]'0.0') {
        return $module.Version.ToString()
    }

    $psd1Path = Join-Path (Split-Path -Parent $module.Path) 'configmap.psd1'
    if (Test-Path $psd1Path) {
        return [string](Import-PowerShellDataFile $psd1Path).ModuleVersion
    }

    return $module.Version.ToString()
}

function Write-InternalHelp {
    param($invocation)

    $commandName = if ($invocation -and $invocation.InvocationName) { $invocation.InvocationName } else { 'qbuild' }
    $commands = Get-ConfigMapInternalCommands -Language build

    $maxNameLength = @($commands.Keys | ForEach-Object { ([string]$_).Length } | Measure-Object -Maximum).Maximum
    if ($null -eq $maxNameLength) { $maxNameLength = 0 }
    $maxNameLength = [Math]::Max($maxNameLength, 12)

    Write-Host ""
    Write-Host "$($commandName.ToUpper())" -ForegroundColor Cyan
    Write-Host "A command line tool to manage build scripts" -ForegroundColor Gray
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "    $commandName <COMMAND> [OPTIONS]" -ForegroundColor White
    Write-Host "    $commandName <process>[.<step>] [process options]  # when _settings.process=<name> (e.g. steps)" -ForegroundColor White
    Write-Host "    $commandName -Version" -ForegroundColor White
    Write-Host ""
    Write-Host "INTERNAL COMMANDS:" -ForegroundColor Yellow

    foreach ($item in $commands.GetEnumerator()) {
        $name = [string]$item.Key
        $script = $item.Value
        $description = ""
        if ($script -is [System.Collections.IDictionary] -and $script.description) {
            $description = $script.description
        }

        Write-CommandHelpLine $name $description (Get-CommandHelpParamInfo $script) $maxNameLength
    }
}

function Write-MapHelp {
    param([System.Collections.IDictionary]$map, $invocation, [ValidateSet("build", "conf")]$language = "build")
    $commandName = $invocation.InvocationName
    $operationContext = New-ConfigMapOperationContext
    $relativeMapPath = Get-RelativeMapDisplayPath -Map $map

    $writeHeader = {
        Write-Host ""
        Write-Host "$($commandName.ToUpper())" -ForegroundColor Cyan
        Write-Host "A command line tool to manage $language scripts" -ForegroundColor Gray
        if ($relativeMapPath) {
            Write-Host "Map: $relativeMapPath" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Host "USAGE:" -ForegroundColor Yellow
        Write-Host "    $commandName <COMMAND> [OPTIONS]" -ForegroundColor White
        Write-Host ""
        Write-Host "COMMANDS:" -ForegroundColor Yellow
    }

    $tryWriteProcessListEntry = {
        param($name, $entryValue)
        if ($language -ne 'build') {
            return $false
        }

        $settings = Get-ConfigMapSettingsForPath -Map $map -Path $name -OperationContext $operationContext
        $handler = Get-ConfigMapProcessHandler -Name $settings.Process
        if ($null -ne $handler) {
            if ($null -ne $handler.WriteListEntry) {
                & $handler.WriteListEntry @{
                    Name             = $name
                    Entry            = $entryValue
                    Map              = $map
                    Invocation       = $invocation
                    Language         = $language
                    OperationContext = $operationContext
                } | Out-Null
                return $true
            }
            return $false
        }

        # Nested step paths under an external process entry are shown inside the status tree
        if ($name -match '\.' -and -not (Get-EntryProcess $entryValue -Default '')) {
            return $true
        }

        try {
            $mapPath = Resolve-MapPath -Map $map
            if (-not $mapPath) {
                return $false
            }
            $splat = ConvertTo-ConfigMapProcessSplat -MapPath $mapPath -Command 'list' -RemainingArguments @($name)
            Invoke-ConfigMapProcessCli `
                -ProcessName (Get-ConfigMapProcessCliName -ProcessName $settings.Process) `
                -Splat $splat | Out-Null
            return $true
        }
        catch {
            # No map path (in-memory) or process command missing — skip process list row
            return $false
        }
    }

    $cache = Get-ConfigMapDiscoveryCache -Map $map -Language $language
    if ($cache) {
        $scriptItems = @($cache.entries.hierarchical)
        if ($map -isnot [System.Collections.Specialized.OrderedDictionary]) {
            $scriptItems = @($scriptItems | Sort-Object { [string]$_.key })
        }
        $maxNameLength = @($scriptItems | ForEach-Object { ([string]$_.key).Length } | Measure-Object -Maximum).Maximum
        if ($null -eq $maxNameLength) { $maxNameLength = 0 }
        $maxNameLength = [Math]::Max($maxNameLength, 12)

        & $writeHeader

        foreach ($item in $scriptItems) {
            $name = [string]$item.key
            $entryValue = Get-MapEntry $map $name -language $language -OperationContext $operationContext
            if (& $tryWriteProcessListEntry $name $entryValue) {
                continue
            }

            $description = [string]$item.description
            $argList = @($item.parameters) | Where-Object { $_ } | ForEach-Object { "-$($_.name)" }
            $paramInfo = ($argList -join " ")
            Write-CommandHelpLine $name $description $paramInfo $maxNameLength
        }
        return
    }

    $scripts = Get-CompletionList $map -language $language

    # Calculate max command name length for alignment
    $maxNameLength = ($scripts.Keys | Measure-Object -Property Length -Maximum).Maximum
    $maxNameLength = [Math]::Max($maxNameLength, 12) # Minimum width

    & $writeHeader

    # Keep definition order for [ordered] maps; sort alphabetically otherwise
    $scriptItems = if ($map -is [System.Collections.Specialized.OrderedDictionary]) {
        @($scripts.GetEnumerator())
    }
    else {
        @($scripts.GetEnumerator() | Sort-Object Name)
    }

    foreach ($item in $scriptItems) {
        $name = $item.Name
        $script = $item.Value

        if (& $tryWriteProcessListEntry $name $script) {
            continue
        }

        $description = ""
        if ($script -is [System.Collections.IDictionary] -and $script.description) {
            $description = $script.description
        }

        Write-CommandHelpLine $name $description (Get-CommandHelpParamInfo $script) $maxNameLength
    }
}

function Write-Help {
    param($invocation, [string]$mapPath)
    $commandName = $invocation.InvocationName
    $mapKind = if ($mapPath -match 'process') { 'process' } else { 'build' }

    Write-Host "No $mapKind map file found at '$mapPath'"
    Write-Host ""
    Write-Host "To create a new $mapKind map file, run:"
    Write-Host "  $commandName !init"
    Write-Host ""
    Write-Host "This will create a sample $mapPath file with basic $mapKind scripts."
}

function Write-ChooseSubcommand {
    <#
    .SYNOPSIS
        Emits a friendly message prompting the user to choose a subcommand for
        a parent entry that has no 'exec' command defined.
    #>
    param(
        [string]$parentKey,
        [System.Collections.IDictionary]$parentEntry,
        $invocation,
        [ValidateSet("build", "conf")]$language = "build"
    )

    $commandName = $invocation ? $invocation.InvocationName : $language
    $children = Get-CompletionList $parentEntry -language $language

    Write-Host ""
    Write-Host "Entry '$parentKey' has no 'exec' command for default action." -ForegroundColor Yellow
    Write-Host "Please choose a subcommand to run:" -ForegroundColor Yellow
    Write-Host ""

    foreach ($childName in $children.Keys) {
        Write-Host "    $commandName " -NoNewline
        Write-Host "$parentKey.$childName" -ForegroundColor Green
    }
}
