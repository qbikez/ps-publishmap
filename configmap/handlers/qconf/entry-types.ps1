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

        # Short form: "user-secrets:{csproj}" → @{ type = 'user-secrets'; csproj = ... }
        if ($template -match '^(?i)user-secrets:(.*)$') {
            $csproj = $Matches[1].Trim()
            if ([string]::IsNullOrWhiteSpace($csproj)) {
                throw "Config entry template 'user-secrets:' requires a csproj path."
            }
            return @{
                type   = 'user-secrets'
                csproj = $csproj
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
        [string]$TypeName,
        [string]$Key = 'file'
    )

    $file = $Template[$Key]
    if ($file -isnot [string] -or [string]::IsNullOrWhiteSpace($file)) {
        throw "Config entry type '$TypeName' requires a $Key path."
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
        [string]$TypeName,
        [string]$Key = 'file'
    )

    $template = Get-ConfigEntryTemplate -Entry $Entry
    if ($null -eq $template) {
        throw "Config entry has no _template."
    }

    return Resolve-ConfigEntryFile -Entry $Entry -Template $template -TypeName $TypeName -Key $Key
}

function Assert-UserSecretsProject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Csproj
    )

    # `dotnet user-secrets --project` accepts a project file or the directory containing one.
    if (-not (Test-Path -LiteralPath $Csproj)) {
        throw "user-secrets csproj not found: $Csproj"
    }
}

function Find-ActiveSecretOption {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Csproj,
        [Parameter(Mandatory = $true)]
        $Options
    )

    Assert-UserSecretsProject -Csproj $Csproj

    $secrets = get-user-secrets $Csproj
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list user secrets for '$Csproj'. Does it define a UserSecretsId, and is 'dotnet user-secrets' available?"
    }

    $active = $null
    $valueObject = [ordered]@{}

    foreach ($optionSet in $Options.Keys) {
        $option = $Options[$optionSet]
        if ($option -isnot [System.Collections.IDictionary]) { continue }

        $isMatch = $true
        foreach ($key in @($option.Keys)) {
            if ("$key".StartsWith('__')) { continue }

            if (-not $valueObject.Contains($key)) {
                $valueObject[$key] = $secrets[$key]
            }
            $currentValue = $valueObject[$key]
            $optionValue = $option[$key]
            if ("$optionValue".StartsWith('user-secrets:')) {
                $optionValue = resolve-value $optionValue -secrets $secrets 3>$null
                # Still a reference means the secret is missing, so this option cannot be active.
                if (test-isSpecialValue $optionValue) { $isMatch = $false }
            }

            if ($null -eq $currentValue) {
                $isMatch = $false
                continue
            }

            if ($isMatch -and $currentValue -ne $optionValue -and -not (test-isSpecialValue $optionValue)) {
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

function Set-UserSecretOption {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Csproj,
        $Values
    )

    if ($Values -isnot [System.Collections.IDictionary]) {
        throw "user-secrets option value must be a hashtable of secret keys."
    }

    Assert-UserSecretsProject -Csproj $Csproj

    $secrets = get-user-secrets $Csproj

    # Resolve everything first so a missing reference writes nothing.
    $resolved = [ordered]@{}
    foreach ($key in @($Values.Keys)) {
        if ("$key".StartsWith('__')) { continue }

        $secretValue = resolve-value $Values[$key] -secrets $secrets 3>$null
        if ($null -eq $secretValue -or (test-isSpecialValue $secretValue)) {
            throw "Cannot set user secret '$key': '$($Values[$key])' was not found for '$Csproj'."
        }
        $resolved[$key] = $secretValue
    }

    foreach ($key in $resolved.Keys) {
        $null = dotnet user-secrets set "$key" "$($resolved[$key])" --project $Csproj 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to set user secret '$key' for '$Csproj'."
        }
    }
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
        Accepts `_template` as a hashtable (`type`/`file`, or `type`/`csproj` for
        `user-secrets`) or short string (`appsettings:{filepath}`, `dotenv:{filepath}`
        or `user-secrets:{csproj}`). Leaves an author-supplied
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

    $pathKey = if ($typeName -eq 'user-secrets') { 'csproj' } else { 'file' }
    $null = Resolve-ConfigEntryFile -Entry $Entry -Template $template -TypeName $typeName -Key $pathKey
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
