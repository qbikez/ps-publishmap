#requires -version 7.0

function Get-ConfigEntryTemplate {
    param(
        $Entry
    )

    if ($Entry -isnot [System.Collections.IDictionary]) { return $null }
    if (-not $Entry.Contains('_template')) { return $null }

    $template = $Entry._template
    if ($template -is [System.Collections.IDictionary]) {
        return $template
    }

    if ($template -is [string]) {
        # Short form: "appsettings:{filepath}" → @{ type = 'appconfig'; file = ... }
        if ($template -match '^(?i)appsettings:(.+)$') {
            $file = $Matches[1].Trim()
            if ([string]::IsNullOrWhiteSpace($file)) {
                throw "Config entry template 'appsettings:' requires a file path."
            }
            return @{
                type = 'appconfig'
                file = $file
            }
        }

        # Short form: "dotenv:{filepath}" → @{ type = 'dotenv'; file = ... }
        if ($template -match '^(?i)dotenv:(.+)$') {
            $file = $Matches[1].Trim()
            if ([string]::IsNullOrWhiteSpace($file)) {
                throw "Config entry template 'dotenv:' requires a file path."
            }
            return @{
                type = 'dotenv'
                file = $file
            }
        }

        throw "Unknown config entry template '$template'."
    }

    return $null
}

function Resolve-ConfigEntryFile {
    param(
        $Entry,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Template,
        [Parameter(Mandatory = $true)]
        [string]$TypeName
    )

    $file = $Template.file
    if ($file -isnot [string] -or [string]::IsNullOrWhiteSpace($file)) {
        throw "Config entry type '$TypeName' requires a file path."
    }

    if ([System.IO.Path]::IsPathRooted($file)) {
        return $file
    }

    $baseDir = if ($Entry._baseDir) { [string]$Entry._baseDir } else { (Get-Location).Path }
    return [System.IO.Path]::GetFullPath((Join-Path $baseDir $file))
}

function Get-ConfigEntryTemplateFile {
    param(
        [Parameter(Mandatory = $true)]
        $Entry,
        [Parameter(Mandatory = $true)]
        [string]$TypeName
    )

    $template = Get-ConfigEntryTemplate -Entry $Entry
    if ($null -eq $template) {
        throw "Config entry has no _template."
    }

    return Resolve-ConfigEntryFile -Entry $Entry -Template $template -TypeName $TypeName
}

function Set-AppConfigOption {
    param(
        [Parameter(Mandatory = $true)]
        [string]$File,
        $Values
    )

    if ($Values -isnot [System.Collections.IDictionary]) {
        throw "appconfig option value must be a hashtable of setting keys."
    }

    $directory = Split-Path -Parent $File
    foreach ($key in @($Values.Keys)) {
        if ("$key".StartsWith('__')) { continue }

        $settingValue = resolve-value $Values[$key] -dir $directory
        set-appsettings -file $File -path $key -value $settingValue
    }
}

function Find-ActiveEnvOption {
    param(
        [Parameter(Mandatory = $true)]
        [string]$File,
        [Parameter(Mandatory = $true)]
        $Options
    )

    $active = $null
    $valueObject = [ordered]@{}

    foreach ($optionSet in $Options.Keys) {
        $option = $Options[$optionSet]
        if ($option -isnot [System.Collections.IDictionary]) { continue }

        $isMatch = $true
        foreach ($key in @($option.Keys)) {
            if ("$key".StartsWith('__')) { continue }

            if (-not $valueObject.Contains($key)) {
                $valueObject[$key] = get-envsetting $key $File
            }
            $currentValue = $valueObject[$key]
            $optionValue = $option[$key]

            if ($null -eq $currentValue) {
                $isMatch = $false
                continue
            }

            if ($isMatch -and $currentValue -is [string] -and $currentValue -ne $optionValue -and -not (test-isSpecialValue $optionValue)) {
                $isMatch = $false
            }
        }

        if ($isMatch) {
            $active = $optionSet
            break
        }
    }

    return @{ Value = $valueObject; Active = $active }
}

function Set-DotEnvOption {
    param(
        [Parameter(Mandatory = $true)]
        [string]$File,
        $Values
    )

    if ($Values -isnot [System.Collections.IDictionary]) {
        throw "dotenv option value must be a hashtable of environment variable keys."
    }

    $directory = Split-Path -Parent $File
    foreach ($key in @($Values.Keys)) {
        if ("$key".StartsWith('__')) { continue }

        $settingValue = resolve-value $Values[$key] -dir $directory
        set-envsetting $key $settingValue $File
    }
}

function ConvertFrom-DotEnvLine {
    <#
    .SYNOPSIS
        Parse one dotenv line into @{ Key; Value }, or $null for blanks, comments and non-assignments.
    #>
    param([string]$Line)

    if ($Line -notmatch '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_.]*)\s*=\s*(.*?)\s*$') { return $null }

    $key = $Matches[1]
    $value = $Matches[2]
    if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") {
        $value = $Matches[1]
    }
    else {
        # An unquoted value ends at an inline comment.
        $value = ($value -replace '\s+#.*$', '')
    }

    return @{ Key = $key; Value = $value }
}

function Read-DotEnvOptionValues {
    param(
        [Parameter(Mandatory = $true)]
        [string]$File
    )

    $values = [ordered]@{}
    foreach ($line in @(Get-Content -LiteralPath $File)) {
        $parsed = ConvertFrom-DotEnvLine $line
        if ($parsed) { $values[$parsed.Key] = $parsed.Value }
    }
    return $values
}

function Get-DotEnvEntryOptions {
    <#
    .SYNOPSIS
        Derive options from the dotenv files that sit next to a dotenv _template entry's file.

    .DESCRIPTION
        For `_template = "dotenv:.env"` every sibling `.env.<name>` becomes option `<name>`.
        A `.example`, `.sample` or `.template` suffix is ignored (`.env.dev.example` is option
        `dev`); a bare `.env.example` becomes option `example`. When both `.env.dev` and
        `.env.dev.example` exist, the real file wins. Returns $null when the entry is not a
        dotenv template or nothing usable is found, so explicit `options` are never replaced.
    #>
    param(
        $Entry
    )

    if ($Entry -isnot [System.Collections.IDictionary] -or -not $Entry.Contains('_template')) { return $null }

    try {
        $template = Get-ConfigEntryTemplate -Entry $Entry
        if ($null -eq $template -or $template.type -ne 'dotenv') { return $null }
        $target = Resolve-ConfigEntryFile -Entry $Entry -Template $template -TypeName 'dotenv'
    }
    catch {
        Write-Verbose "dotenv option discovery skipped: $($_.Exception.Message)"
        return $null
    }

    $directory = Split-Path -Parent $target
    $leaf = Split-Path -Leaf $target
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return $null }

    $templateSuffix = '\.(example|sample|template)$'
    $candidates = Get-ChildItem -LiteralPath $directory -File -Force |
        Where-Object { $_.Name -ne $leaf -and $_.Name.StartsWith("$leaf.", [System.StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object { $_.Name -match $templateSuffix }, Name

    $options = [ordered]@{}
    foreach ($file in $candidates) {
        $name = $file.Name.Substring($leaf.Length + 1) -replace $templateSuffix, ''
        if ($options.Contains($name)) { continue }

        $values = Read-DotEnvOptionValues -File $file.FullName
        if ($values.Count -gt 0) { $options[$name] = $values }
    }

    if ($options.Count -eq 0) { return $null }
    return $options
}

function Get-ConfigEntryTypeCommands {
    <#
    .SYNOPSIS
        Built-in get/set implementations for Entry._template types.
    #>
    return . "$PSScriptRoot\entry-types.map.ps1"
}

function Add-ConfigEntryTypeCommands {
    <#
    .SYNOPSIS
        Fill in get and set from Entry._template when the map did not supply them.

    .DESCRIPTION
        Accepts `_template` as a hashtable (`type`/`file`) or short string
        (`appsettings:{filepath}` or `dotenv:{filepath}`). Leaves an author-supplied
        get or set in place. Always stashes the template get/set on
        Entry._internal.base so overrides can call them via $_context.base.
    #>
    param(
        $Entry
    )

    if ($Entry -isnot [System.Collections.IDictionary]) { return }

    $template = Get-ConfigEntryTemplate -Entry $Entry
    if ($null -eq $template -or -not $template.Contains('type') -or -not $template.type) { return }

    $typeName = [string]$template.type
    $typeCommands = Get-ConfigEntryTypeCommands
    if (-not $typeCommands.Contains($typeName)) {
        throw "Unknown config entry type '$typeName'."
    }

    $null = Resolve-ConfigEntryFile -Entry $Entry -Template $template -TypeName $typeName
    $commands = $typeCommands[$typeName]

    if (-not $Entry.Contains('_internal') -or $Entry._internal -isnot [System.Collections.IDictionary]) {
        $Entry._internal = @{}
    }
    $Entry._internal.base = @{
        get = $commands.get
        set = $commands.set
    }

    if ($Entry.get -isnot [scriptblock]) {
        $Entry.get = $commands.get
    }
    if ($Entry.set -isnot [scriptblock]) {
        $Entry.set = $commands.set
    }
}
