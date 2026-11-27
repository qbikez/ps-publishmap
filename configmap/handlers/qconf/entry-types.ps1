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
        [string]$TypeName
    )

    $key = if ($TypeName -eq 'user-secrets') { 'csproj' } else { 'file' }
    $file = $Template[$key]
    if ($file -isnot [string] -or [string]::IsNullOrWhiteSpace($file)) {
        throw "Config entry type '$TypeName' requires a $key path."
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

function Find-MatchingOption {
    <#
    .SYNOPSIS
        Find the first option whose keys all match the current values.

    .PARAMETER GetValue
        Reads the current value of a key; returns $null when it is not set.

    .PARAMETER GetExpected
        Maps an option value to the value to compare against; $null means it cannot match.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Options,
        [Parameter(Mandatory = $true)]
        [scriptblock]$GetValue,
        [scriptblock]$GetExpected = { param($optionValue) $optionValue }
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
                $valueObject[$key] = & $GetValue $key
            }
            $currentValue = $valueObject[$key]
            $expectedValue = & $GetExpected $option[$key]

            if ($null -eq $currentValue) {
                $isMatch = $false
                continue
            }

            if ($isMatch -and $currentValue -is [string] -and $currentValue -ne $expectedValue -and -not (test-isSpecialValue $expectedValue)) {
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

function Get-ProjectUserSecret {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Csproj
    )

    Import-ConfigMapPlugin 'user-secrets'
    $secrets = get-user-secrets $Csproj
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list user secrets for '$Csproj'. Does it define a UserSecretsId, and is 'dotnet user-secrets' available?"
    }

    return $secrets
}

function Find-ActiveSecretOption {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Csproj,
        [Parameter(Mandatory = $true)]
        $Options
    )

    Assert-UserSecretsProject -Csproj $Csproj
    $secrets = Get-ProjectUserSecret -Csproj $Csproj

    return Find-MatchingOption -Options $Options -GetValue { param($key) $secrets[$key] } -GetExpected {
        param($optionValue)
        Resolve-UserSecretReference $optionValue $secrets
    }
}

function Resolve-UserSecretReference {
    <#
    .SYNOPSIS
        The value a `user-secrets:` option value stands for, looked up in already-listed secrets;
        $null when the secret is missing. Any other value is returned as is.
    #>
    param($OptionValue, [hashtable]$Secrets)

    if (-not "$OptionValue".StartsWith('user-secrets:')) { return $OptionValue }

    $resolved = resolve-value $OptionValue -secrets $Secrets 3>$null
    # Still a reference means the secret is missing, so this option cannot be active.
    if (test-isSpecialValue $resolved) { return $null }
    return $resolved
}

function Get-ReferencedUserSecret {
    <#
    .SYNOPSIS
        Lists the user secrets once when any of $Values is a `user-secrets:` reference; $null when
        none is, or when listing fails. `-UserSecretsId` reads that store, else the project in `-Directory`.
    #>
    param(
        [object[]]$Values,
        [string]$Directory,
        [string]$UserSecretsId
    )

    if (-not @($Values | Where-Object { "$_".StartsWith('user-secrets:') })) { return $null }

    Import-ConfigMapPlugin 'user-secrets'
    $secrets = get-user-secrets $Directory -Id $UserSecretsId
    if ($LASTEXITCODE -ne 0) {
        Write-Verbose "Failed to list user secrets ($(format-user-secrets-target $Directory -Id $UserSecretsId))."
        return $null
    }
    return $secrets
}

function Get-OptionValueList {
    # Every value of every option, for spotting `user-secrets:` references.
    param($Options)

    foreach ($option in @($Options.Values)) {
        if ($option -is [System.Collections.IDictionary]) { $option.Values }
    }
}

function Resolve-FileOptionValues {
    <#
    .SYNOPSIS
        Resolve every value of an option before a file is written, so a missing
        `user-secrets:` reference throws and writes nothing.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Values,
        [string]$Directory,
        [string]$UserSecretsId
    )

    $references = @($Values.Values | Where-Object { "$_".StartsWith('user-secrets:') })
    $secrets = Get-ReferencedUserSecret -Values $references -Directory $Directory -UserSecretsId $UserSecretsId
    if ($references -and $null -eq $secrets) {
        Import-ConfigMapPlugin 'user-secrets'
        throw "Failed to list user secrets ($(format-user-secrets-target $Directory -Id $UserSecretsId)). Set the template's userSecretsId, or check that the project defines a UserSecretsId and 'dotnet user-secrets' is available."
    }

    $resolved = [ordered]@{}
    foreach ($key in @($Values.Keys)) {
        if ("$key".StartsWith('__')) { continue }

        $value = resolve-value $Values[$key] -dir $Directory -secrets $secrets -userSecretsId $UserSecretsId
        if ("$value".StartsWith('user-secrets:')) {
            throw "Cannot set '$key': user secret '$("$value".Substring('user-secrets:'.Length))' not found ($(format-user-secrets-target $Directory -Id $UserSecretsId))."
        }
        $resolved[$key] = $value
    }
    return $resolved
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

    # Listing spawns dotnet, so skip it unless a value references another secret.
    $hasReference = @($Values.Values | Where-Object { "$_".StartsWith('user-secrets:') }).Count -gt 0
    $secrets = if ($hasReference) { Get-ProjectUserSecret -Csproj $Csproj } else { @{} }

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

    # JSON on stdin merges every key into the store with a single dotnet spawn.
    # dotnet decodes stdin with the console code page (Windows) or locale charset (Unix),
    # so escape non-ASCII to keep the bytes identical under any of them.
    $null = $resolved | ConvertTo-Json -Compress -EscapeHandling EscapeNonAscii | dotnet user-secrets set --project $Csproj 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set user secrets for '$Csproj'."
    }
}

function Set-AppConfigOption {
    param(
        [Parameter(Mandatory = $true)]
        [string]$File,
        $Values,
        [string]$UserSecretsId
    )

    if ($Values -isnot [System.Collections.IDictionary]) {
        throw "appconfig option value must be a hashtable of setting keys."
    }

    $resolved = Resolve-FileOptionValues -Values $Values -Directory (Split-Path -Parent $File) -UserSecretsId $UserSecretsId
    foreach ($key in @($resolved.Keys)) {
        set-appsettings -file $File -path $key -value $resolved[$key]
    }
}

function Find-ActiveAppConfigOption {
    param(
        [Parameter(Mandatory = $true)]
        [string]$File,
        [Parameter(Mandatory = $true)]
        $Options,
        [string]$UserSecretsId
    )

    $secrets = Get-ReferencedUserSecret -Values (Get-OptionValueList $Options) -Directory (Split-Path -Parent $File) -UserSecretsId $UserSecretsId
    return Find-ActiveOption -file $File -options $Options -secrets $secrets
}

function Find-ActiveEnvOption {
    param(
        [Parameter(Mandatory = $true)]
        [string]$File,
        [Parameter(Mandatory = $true)]
        $Options,
        [string]$UserSecretsId
    )

    # With the secrets listed, `user-secrets:` values match by their value; without, they match anything.
    $secrets = Get-ReferencedUserSecret -Values (Get-OptionValueList $Options) -Directory (Split-Path -Parent $File) -UserSecretsId $UserSecretsId
    $getExpected = if ($null -eq $secrets) { { param($optionValue) $optionValue } } else {
        { param($optionValue) Resolve-UserSecretReference $optionValue $secrets }
    }
    return Find-MatchingOption -Options $Options -GetValue { param($key) get-envsetting $key $File } -GetExpected $getExpected
}

function Set-DotEnvOption {
    param(
        [Parameter(Mandatory = $true)]
        [string]$File,
        $Values,
        [string]$UserSecretsId
    )

    if ($Values -isnot [System.Collections.IDictionary]) {
        throw "dotenv option value must be a hashtable of environment variable keys."
    }

    $resolved = Resolve-FileOptionValues -Values $Values -Directory (Split-Path -Parent $File) -UserSecretsId $UserSecretsId
    foreach ($key in @($resolved.Keys)) {
        set-envsetting $key $resolved[$key] $File
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

function Read-DotEnvKeyInfo {
    <#
    .SYNOPSIS
        Read a dotenv file as key -> @{ Value; Description }, where Description is the
        comment line(s) directly above the key.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$File
    )

    $info = [ordered]@{}
    $comments = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @(Get-Content -LiteralPath $File)) {
        if ($line -match '^\s*#\s?(.*)$') {
            $comments.Add($Matches[1].Trim())
            continue
        }

        $parsed = ConvertFrom-DotEnvLine $line
        if ($parsed) {
            $info[$parsed.Key] = @{ Value = $parsed.Value; Description = ($comments -join ' ') }
        }
        $comments.Clear()
    }
    return $info
}

function Resolve-DotEnvKeysFile {
    param(
        $Keys,
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    $directory = Split-Path -Parent $Target
    if ($Keys -is [string] -and $Keys -ne 'auto') {
        $candidates = @([System.IO.Path]::IsPathRooted($Keys) ? $Keys : (Join-Path $directory $Keys))
    }
    else {
        $candidates = 'example', 'sample', 'template' | ForEach-Object { "$Target.$_" }
    }

    return $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

function New-DotEnvParentContext {
    <#
    .SYNOPSIS
        The $_context a generated key entry passes to its parent's get/set: self and base are the
        parent's, and envKey names the key so a parent override can tell it from a preset switch.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ChildEntry,
        [System.Collections.IDictionary]$ChildContext
    )

    $parent = $ChildEntry._internal.parent
    Add-ConfigEntryTypeCommands -Entry $parent

    $context = if ($ChildContext) { $ChildContext.Clone() } else { @{} }
    $context.self = $parent
    $context.base = $parent._internal.base
    $context.envKey = $ChildEntry._internal.envKey
    return $context
}

function Get-DotEnvKeyFromParent {
    <#
    .SYNOPSIS
        Read one key through the parent entry's get (template or author override).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ChildEntry,
        $Ctx,
        [System.Collections.IDictionary]$ChildContext
    )

    $context = New-DotEnvParentContext -ChildEntry $ChildEntry -ChildContext $ChildContext
    $parent = $context.self
    $envKey = $context.envKey

    # The parent's own presets, plus one that never matches but makes the built-in get read this
    # key even when no preset contains it.
    $options = [ordered]@{}
    $parentOptions = Get-CompletionList $parent -listKey 'options' -language 'conf' -maxDepth 1
    foreach ($name in @($parentOptions.Keys)) { $options[$name] = $parentOptions[$name] }
    $options['__key'] = @{ $envKey = $null }

    $result = & $parent.get $Ctx $options $context
    if ($result -isnot [System.Collections.IDictionary] -or $result.Value -isnot [System.Collections.IDictionary]) {
        throw "Entry '$($ChildEntry._internal.parentName)' get must return @{ Value = @{ ... }; Active = ... } for its per-key entry '$envKey'."
    }
    return $result.Value[$envKey]
}

function Set-DotEnvKeyThroughParent {
    <#
    .SYNOPSIS
        Write one key through the parent entry's set (template or author override), passing
        $key = $null and a one-key $value.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ChildEntry,
        $Ctx,
        $NewValue,
        [System.Collections.IDictionary]$ChildContext
    )

    $context = New-DotEnvParentContext -ChildEntry $ChildEntry -ChildContext $ChildContext
    $null = & $context.self.set $Ctx $null ([ordered]@{ $context.envKey = $NewValue }) $context
}

function New-DotEnvKeyEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        $Info,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Parent,
        [Parameter(Mandatory = $true)]
        [string]$ParentName,
        [string]$BaseDir
    )

    # No _template here: it would make the child discover the parent's .env.<name> presets as options.
    # get/set go through the parent so its overrides also apply to single keys.
    $description = $Info.Description ? $Info.Description : "$Key"
    $entry = [ordered]@{
        description = "$description (example: $($Info.Value))"
        _internal   = @{ envKey = $Key; parent = $Parent; parentName = $ParentName }
        get         = {
            param($ctx, $options, $_context)
            Get-DotEnvKeyFromParent -ChildEntry $_context.self -Ctx $ctx -ChildContext $_context
        }
        set         = {
            param($ctx, $key, $value, $_context)
            Set-DotEnvKeyThroughParent -ChildEntry $_context.self -Ctx $ctx -NewValue $key -ChildContext $_context
        }
    }
    if ($BaseDir) { $entry._baseDir = $BaseDir }
    return $entry
}

function Expand-DotEnvKeyEntries {
    <#
    .SYNOPSIS
        Prepare dotenv _template entries when a map loads: attach lazily discovered
        options and add one child entry per key for entries that set `keys`.

    .DESCRIPTION
        `keys = 'auto'` reads `<file>.example` (or `.sample` / `.template`); any other string
        names the file to read keys from. `exclude` (string or array, `-like` wildcards allowed)
        lists keys that get no child entry and are left out of the parent value. Children are named after the key (`api.API_URL`),
        read and write just that key through the parent's get/set, and never replace an entry the map already defines.
        Explicit `options` are left alone; otherwise `options` becomes a scriptblock that
        reads the sibling `.env.*` files when asked, so completion sees file changes.
    #>
    param(
        [System.Collections.IDictionary]$Map
    )

    foreach ($name in @($Map.Keys)) {
        $entry = $Map[$name]
        if ($entry -isnot [System.Collections.IDictionary] -or "$name".StartsWith('_') -or $name -eq 'options') { continue }

        $template = $null
        try { $template = Get-ConfigEntryTemplate -Entry $entry } catch { Write-Verbose "dotenv key discovery skipped: $($_.Exception.Message)" }
        if ($template -and $template.type -eq 'dotenv' -and -not $entry.Contains('options')) {
            # A closure runs outside this module's scope, so it must carry the command object itself.
            $presetEntry = $entry
            $discover = Get-Command Get-DotEnvEntryOptions
            $entry.options = { $discovered = & $discover -Entry $presetEntry; $discovered ? $discovered : [ordered]@{} }.GetNewClosure()
        }
        if ($template -and $template.type -eq 'dotenv' -and $template.Contains('keys') -and $template.keys) {
            $target = Resolve-ConfigEntryFile -Entry $entry -Template $template -TypeName 'dotenv'
            $keysFile = Resolve-DotEnvKeysFile -Keys $template.keys -Target $target
            if ($keysFile) {
                $info = Read-DotEnvKeyInfo -File $keysFile
                $excluded = @($template.exclude | Where-Object { $_ })
                foreach ($key in $info.Keys) {
                    if ($entry.Contains($key)) { continue }
                    if ($excluded | Where-Object { $key -like $_ }) { continue }
                    $entry[$key] = New-DotEnvKeyEntry -Key $key -Info $info[$key] -Parent $entry -ParentName $name -BaseDir $entry._baseDir
                }
            }
        }

        Expand-DotEnvKeyEntries -Map $entry
    }
}

function Get-ConfigEntryTypeCommands {
    <#
    .SYNOPSIS
        Built-in get/set implementations for Entry._template types.
    #>
    return . "$PSScriptRoot\entry-types.map.ps1"
}

function Test-ConfigEntrySensitive {
    <#
    .SYNOPSIS
        True when the entry's _template type keeps values that `list` must not read.
    #>
    param(
        $Entry
    )

    $template = Get-ConfigEntryTemplate -Entry $Entry
    if ($null -eq $template -or -not $template.type) { return $false }

    $commands = (Get-ConfigEntryTypeCommands)[[string]$template.type]
    return [bool]($commands -and $commands.sensitive)
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
