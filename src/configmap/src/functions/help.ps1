function Write-MapHelp {
    param([System.Collections.IDictionary]$map, $invocation, [ValidateSet("build", "conf")]$language = "build")
    $commandName = $invocation.InvocationName
    $operationContext = New-ConfigMapOperationContext

    $writeDefaultLine = {
        param($name, $description, $paramInfo, $maxNameLength)
        $paddedName = $name.PadRight($maxNameLength)
        Write-Host "    " -NoNewline
        Write-Host "$paddedName" -ForegroundColor Green -NoNewline
        if ($paramInfo) {
            Write-Host " [$paramInfo]" -ForegroundColor DarkGray -NoNewline
        }
        Write-Host "  $description" -ForegroundColor White
    }

    $tryWriteProcessListEntry = {
        param($name, $entryValue)
        if ($language -ne 'build') {
            return $false
        }

        $settings = Get-ConfigMapSettingsForPath -Map $map -Path $name -OperationContext $operationContext
        if ($settings.Process -eq 'qbuild') {
            return $false
        }

        # Nested step paths under a process entry are shown inside the status tree
        if ($name -match '\.' -and -not (Get-EntryProcess $entryValue -Default '')) {
            return $true
        }

        try {
            $mapPath = Resolve-MapPath -Map $map
            if (-not $mapPath) {
                return $false
            }
            $splat = ConvertTo-ConfigMapProcessSplat -MapPath $mapPath -Command 'list' -RemainingArguments @($name)
            Invoke-ConfigMapProcessCli -ProcessName $settings.Process -Splat $splat | Out-Null
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

        Write-Host ""
        Write-Host "$($commandName.ToUpper())" -ForegroundColor Cyan
        Write-Host "A command line tool to manage $language scripts" -ForegroundColor Gray
        Write-Host ""
        Write-Host "USAGE:" -ForegroundColor Yellow
        Write-Host "    $commandName <COMMAND> [OPTIONS]" -ForegroundColor White
        Write-Host ""
        Write-Host "COMMANDS:" -ForegroundColor Yellow

        foreach ($item in $scriptItems) {
            $name = [string]$item.key
            $entryValue = Get-MapEntry $map $name -language $language -OperationContext $operationContext
            if (& $tryWriteProcessListEntry $name $entryValue) {
                continue
            }

            $description = [string]$item.description
            $argList = @($item.parameters) | Where-Object { $_ } | ForEach-Object { "-$($_.name)" }
            $paramInfo = ($argList -join " ")
            & $writeDefaultLine $name $description $paramInfo $maxNameLength
        }
        return
    }

    $scripts = Get-CompletionList $map -language $language

    # Calculate max command name length for alignment
    $maxNameLength = ($scripts.Keys | Measure-Object -Property Length -Maximum).Maximum
    $maxNameLength = [Math]::Max($maxNameLength, 12) # Minimum width

    Write-Host ""
    Write-Host "$($commandName.ToUpper())" -ForegroundColor Cyan
    Write-Host "A command line tool to manage $language scripts" -ForegroundColor Gray
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "    $commandName <COMMAND> [OPTIONS]" -ForegroundColor White
    Write-Host ""
    Write-Host "COMMANDS:" -ForegroundColor Yellow

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

        try {
            $entry = Get-EntryCommand $script "exec"
        }
        catch {
            $entry = $null
        }
        if ($entry -is [scriptblock]) {
            $args = Get-ScriptArgs $entry
        }
        else {
            $args = @{}
        }

        $description = ""
        if ($script -is [System.Collections.IDictionary] -and $script.description) {
            $description = $script.description
        }

        $argList = $args.Keys | % { "-$($_)" }
        $paramInfo = ($argList -join " ")
        & $writeDefaultLine $name $description $paramInfo $maxNameLength
    }
}

function Write-Help {
    param($invocation, [string]$mapPath)
    $commandName = $invocation.Statement

    Write-Host "No build map file found at '$mapPath'"
    Write-Host ""
    Write-Host "To create a new build map file, run:"
    Write-Host "  $commandName init"
    Write-Host ""
    Write-Host "This will create a sample $mapPath file with basic build scripts."
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
