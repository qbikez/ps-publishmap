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

function New-BoundTypeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$File,
        [Parameter(Mandatory = $true)]
        [string]$Body
    )

    # Unbound scriptblocks run in the caller's module scope, so they can see
    # the private type helpers. GetNewClosure would hide those functions.
    $literal = $File.Replace("'", "''")
    [scriptblock]::Create(($Body -replace '\{file\}', $literal))
}

function Add-AppConfigCommands {
    param(
        [Parameter(Mandatory = $true)]
        $Entry,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Template,
        [switch]$NeedsGet,
        [switch]$NeedsSet
    )

    $settingsFile = Resolve-ConfigEntryFile -Entry $Entry -Template $Template -TypeName 'appconfig'

    if ($NeedsGet) {
        $Entry.get = New-BoundTypeCommand -File $settingsFile -Body @'
param($ctx, $options)
Find-ActiveOption -file '{file}' -options $options
'@
    }

    if ($NeedsSet) {
        $Entry.set = New-BoundTypeCommand -File $settingsFile -Body @'
param($ctx, $key, $value)
Set-AppConfigOption -File '{file}' -Values $value
'@
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

function Add-DotEnvCommands {
    param(
        [Parameter(Mandatory = $true)]
        $Entry,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Template,
        [switch]$NeedsGet,
        [switch]$NeedsSet
    )

    $envFile = Resolve-ConfigEntryFile -Entry $Entry -Template $Template -TypeName 'dotenv'

    if ($NeedsGet) {
        $Entry.get = New-BoundTypeCommand -File $envFile -Body @'
param($ctx, $options)
Find-ActiveEnvOption -File '{file}' -Options $options
'@
    }

    if ($NeedsSet) {
        $Entry.set = New-BoundTypeCommand -File $envFile -Body @'
param($ctx, $key, $value)
Set-DotEnvOption -File '{file}' -Values $value
'@
    }
}

function Add-ConfigEntryTypeCommands {
    <#
    .SYNOPSIS
        Fill in get and set from Entry._template when the map did not supply them.

    .DESCRIPTION
        Accepts `_template` as a hashtable (`type`/`file`) or short string
        (`appsettings:{filepath}` or `dotenv:{filepath}`). Leaves an author-supplied
        get or set in place.
    #>
    param(
        $Entry
    )

    if ($Entry -isnot [System.Collections.IDictionary]) { return }

    $template = Get-ConfigEntryTemplate -Entry $Entry
    if ($null -eq $template -or -not $template.Contains('type') -or -not $template.type) { return }

    $needsGet = $Entry.get -isnot [scriptblock]
    $needsSet = $Entry.set -isnot [scriptblock]
    if (-not $needsGet -and -not $needsSet) { return }

    $typeName = [string]$template.type
    switch ($typeName) {
        'appconfig' {
            Add-AppConfigCommands -Entry $Entry -Template $template -NeedsGet:$needsGet -NeedsSet:$needsSet
        }
        'dotenv' {
            Add-DotEnvCommands -Entry $Entry -Template $template -NeedsGet:$needsGet -NeedsSet:$needsSet
        }
        default {
            throw "Unknown config entry type '$typeName'."
        }
    }
}
