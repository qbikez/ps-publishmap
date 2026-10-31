using namespace System.Management.Automation.Language

$script:samplesPath = "$PSScriptRoot/../samples"

function Initialize-ConfigMap([Parameter(Mandatory = $true)] $file) {
    if (Test-Path $file) {
        throw "map file '$file' already exists"
    }

    $defaultConfig = Get-Content $script:samplesPath/_default/.configuration.map.ps1
    Write-Host "Initializing configmap file '$file'"
    $defaultConfig | Out-File $file

    $fullPath = (Get-Item $file).FullName
    $dir = Split-Path $fullPath -Parent
    $defaultUtils = Get-Content $script:samplesPath/_default/.config-utils.ps1
    $defaultUtils | Out-File (Join-Path $dir ".config-utils.ps1")
}


function Initialize-ProcessMap([Parameter(Mandatory = $true)] $file) {
    if (Test-Path $file) {
        throw "map file '$file' already exists"
    }

    $defaultConfig = Get-Content $script:samplesPath/_default/.process.map.ps1 -Raw
    Write-Host "Initializing process map file '$file'"
    $defaultConfig | Out-File $file
}

function Initialize-BuildMap {
    <#
    .SYNOPSIS
        Add the default entries of one process to a build map, creating it if needed, and leave
        entries the map already has alone. Without -Process, create a map from the defaults of
        every process detected in its directory; an existing map is only pointed at !init.<type>.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $file,
        [string]$Process
    )

    $exists = Test-Path -LiteralPath $file
    if (!$Process -and $exists) {
        Write-Host "Map file '$file' already exists, leaving it unchanged. Add a process type's defaults with:"
        $commands = New-ConfigMapInitTypeEntries
        $width = ($commands.Keys | Measure-Object -Property Length -Maximum).Maximum
        foreach ($item in $commands.GetEnumerator()) {
            Write-Host ("  qbuild !init.{0}  {1}" -f $item.Key.PadRight($width), $item.Value.description)
        }
        return
    }

    $directory = Split-Path ([System.IO.Path]::GetFullPath($file, $PWD.Path)) -Parent
    $processes = @(Get-ConfigMapInitProcesses | Where-Object {
            if ($Process) { $_.Name -eq $Process } else { !$_.InitCondition -or (& $_.InitCondition $directory) }
        })
    if ($processes.Count -eq 0) {
        throw "Process '$Process' has no init template."
    }

    $n = [System.Environment]::NewLine
    $content = if ($exists) { Get-Content -LiteralPath $file -Raw } else { "[ordered]@{$n}$n" }

    $commands = @{}
    if ($exists) {
        # Only this file counts: a map found by looking up parent directories is a different map.
        $commands = Import-ConfigMap -Map $file -LookUp:$false | Assert-ConfigMap
        if ($commands.Contains('list')) {
            $commands = $commands['list']
        }
    }

    $missing = [ordered]@{}
    foreach ($handler in $processes) {
        foreach ($item in (Get-MapInitEntries -Path $handler.InitTemplate).GetEnumerator()) {
            if ($commands.Contains($item.Key)) {
                Write-Host "Entry '$($item.Key)' already exists in '$file', skipping"
            }
            else {
                $missing[$item.Key] = $item.Value
            }
        }
    }
    if ($missing.Count -eq 0) {
        return
    }

    $updated = Add-MapEntries -Content $content -Entries $missing -Source $file
    if (!$exists) {
        Write-Host "Initializing buildmap file '$file'"
    }
    $updated | Set-Content -LiteralPath $file -NoNewline
    foreach ($key in $missing.Keys) {
        Write-Host "Added entry '$key' to '$file'"
    }
}

function Get-MapValueAst {
    <#
    .SYNOPSIS
        Unwrap `return`, a bare expression statement and [ordered] down to the value they hold.
    #>
    param($Ast)

    if ($Ast -is [ReturnStatementAst]) { $Ast = $Ast.Pipeline }
    if ($Ast -is [PipelineAst]) { $Ast = $Ast.GetPureExpression() }
    if ($Ast -is [CommandExpressionAst]) { $Ast = $Ast.Expression }
    if ($Ast -is [ConvertExpressionAst]) { $Ast = $Ast.Child }
    return $Ast
}

function Get-MapRootHashtableAst {
    <#
    .SYNOPSIS
        Find the hashtable literal that holds a map's entries: the one the file returns,
        or its `list` container (same rule as Merge-ConfigMapCommands).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $parseErrors = $null
    $ast = [Parser]::ParseInput($Content, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Cannot parse map '$Source': $($parseErrors[0].Message)"
    }

    $statements = @($ast.EndBlock.Statements)
    $root = if ($statements.Count -gt 0) { Get-MapValueAst $statements[-1] }

    if ($root -is [VariableExpressionAst]) {
        $name = $root.VariablePath.UserPath
        $assignments = @($statements | Where-Object {
                $_ -is [AssignmentStatementAst] -and $_.Left -is [VariableExpressionAst] -and $_.Left.VariablePath.UserPath -eq $name
            })
        $root = if ($assignments.Count -gt 0) { Get-MapValueAst $assignments[-1].Right }
    }

    if ($root -is [HashtableAst]) {
        $list = @($root.KeyValuePairs | Where-Object { $_.Item1.Value -eq 'list' })
        if ($list.Count -gt 0) {
            $root = Get-MapValueAst $list[0].Item2
        }
    }

    if ($root -isnot [HashtableAst]) {
        throw "Cannot add entries to map '$Source': its entries are not in a hashtable literal the file returns. Add them by hand."
    }
    return $root
}

function Get-MapInitEntries {
    <#
    .SYNOPSIS
        Read an init template as an ordered dictionary of entry name -> entry source text.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $content = Get-Content -LiteralPath $Path -Raw
    $entries = [ordered]@{}
    foreach ($pair in (Get-MapRootHashtableAst -Content $content -Source $Path).KeyValuePairs) {
        $start = $pair.Item1.Extent.StartOffset
        $entries[[string]$pair.Item1.Value] = $content.Substring($start, $pair.Item2.Extent.EndOffset - $start)
    }
    return $entries
}

function Add-MapEntries {
    <#
    .SYNOPSIS
        Insert entry source text before a map's closing brace, leaving the rest of the file as written.
        Map files hold scriptblocks and comments, so they are edited as text rather than re-serialized.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entries,
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $root = Get-MapRootHashtableAst -Content $Content -Source $Source
    $newLine = if ($Content.Contains("`r`n")) { "`r`n" } else { "`n" }

    $head = $Content.Substring(0, $root.Extent.EndOffset - 1)
    $tail = $Content.Substring($root.Extent.EndOffset - 1)
    # Template text starts at the key, with its later lines indented one level already.
    $indent = [regex]::Match($head, '(?<=\n)[ \t]*$').Value

    $blocks = foreach ($text in $Entries.Values) {
        $lines = @($text -split '\r?\n' | ForEach-Object { if ($_) { "$indent$_" } else { '' } })
        $lines[0] = "    $($lines[0])"
        $lines -join $newLine
    }

    $body = $head.TrimEnd()
    $separator = if ($body.EndsWith('{')) { $newLine } else { "$newLine$newLine" }
    $updated = $body + $separator + ($blocks -join "$newLine$newLine") + $newLine + $indent + $tail

    [void](Get-MapRootHashtableAst -Content $updated -Source $Source)
    return $updated
}
