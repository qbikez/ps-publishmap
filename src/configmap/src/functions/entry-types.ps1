#requires -version 7.0

function Resolve-ConfigEntryFile {
    param(
        $Entry,
        [Parameter(Mandatory = $true)]
        [string]$TypeName
    )

    $file = $Entry.file
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
        [switch]$NeedsGet,
        [switch]$NeedsSet
    )

    $settingsFile = Resolve-ConfigEntryFile -Entry $Entry -TypeName 'appconfig'

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

function Add-ConfigEntryTypeCommands {
    <#
    .SYNOPSIS
        Fill in get and set from a built-in entry type when the map did not supply them.
    #>
    param(
        $Entry
    )

    if ($Entry -isnot [System.Collections.IDictionary]) { return }
    if (-not $Entry.Contains('type') -or -not $Entry.type) { return }

    $needsGet = $Entry.get -isnot [scriptblock]
    $needsSet = $Entry.set -isnot [scriptblock]
    if (-not $needsGet -and -not $needsSet) { return }

    $typeName = [string]$Entry.type
    switch ($typeName) {
        'appconfig' {
            Add-AppConfigCommands -Entry $Entry -NeedsGet:$needsGet -NeedsSet:$needsSet
        }
        default {
            throw "Unknown config entry type '$typeName'."
        }
    }
}
