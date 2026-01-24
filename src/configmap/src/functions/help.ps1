function Write-MapHelp {
    param([System.Collections.IDictionary]$map, $invocation, [ValidateSet("build", "conf")]$language = "build")
    $commandName = $invocation.InvocationName
    $scripts = Get-CompletionList $map -reservedKeys $script:languages.$language.reservedKeys

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

    # Sort scripts alphabetically
    $sortedScripts = $scripts.GetEnumerator() | Sort-Object Name

    foreach ($item in $sortedScripts) {
        $name = $item.Name
        $script = $item.Value
        try {
            $entry = Get-EntryCommand $script
        }
        catch {
            $entry = $null
        }
        $args = $entry ? (Get-ScriptArgs $entry) : @{}

        # Format command name with proper padding
        $paddedName = $name.PadRight($maxNameLength)

        # Get description
        $description = ""
        if ($script -is [System.Collections.IDictionary] -and $script.description) {
            $description = $script.description
        }

        $argList = $args.Keys | % { "-$($_)" }
        $paramInfo = ($argList -join " ")

        Write-Host "    " -NoNewline
        Write-Host "$paddedName" -ForegroundColor Green -NoNewline
        if ($paramInfo) {
            Write-Host " [$paramInfo]" -ForegroundColor DarkGray -NoNewline
        }
        Write-Host "  $description" -ForegroundColor White
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
