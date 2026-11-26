#Requires -Version 7.0

# Helpers used by the qconf entry types (appsettings, dotenv and user-secrets templates).
# Map scriptblocks run in module scope, so these names are also part of the documented
# map contract (skills/qbuild-templates/SKILL.md, samples/dotenv). Keep the names.
# Resolve-ConfigMapValue is the exported, public way to resolve value references.

function get-appsettings(
    [Parameter(Mandatory = $true, ParameterSetName = "file")][string]$file,
    [Parameter(Mandatory = $true, ParameterSetName = "settings")][object]$appSettings,
    $path = ""
) {
    return get-appsetting -file:$file -appSettings:$appSettings -path:$path
}

function Get-AppSetting(
    [Parameter(Mandatory = $false)][string]$file,
    [Parameter(Mandatory = $false)][object]$appSettings,
    [Parameter(Mandatory = $true)][string] $path
) {
    try {
        if (!$appSettings) {
            if (!$file) {
                throw "Either appSettings or file (or both) must be provided"
            }
            if (!(Test-Path $file)) {
                throw "File not found: $file"
            }
            $appSettings = get-content $file | convertfrom-json
        }

        $json = $appSettings

        $components = $path.split(":")
        $node = $json
        foreach ($component in $components) {
            if (!$component) {
                continue
            }

            $node = $node.$component
        }

        return $node
    }
    catch {
        Write-Error "Failed to get app settings from $file at path '$path': $($_.Exception.Message)"
        throw
    }
}

function set-appsettings(
    [Parameter(Mandatory = $true)] $file,
    [Parameter(Mandatory = $true)] $path,
    [Parameter(Mandatory = $true)] $value
) {
    try {
        if (!(Test-Path $file)) {
            throw "File not found: $file"
        }
        
        $json = get-content $file | convertfrom-json -AsHashtable

        $components = $path.split(":", [System.StringSplitOptions]::RemoveEmptyEntries)
        $node = $json
        for ($i = 0; $i -lt $components.Count - 1; $i++) {
            $component = $components[$i]
            if ($node.$component -eq $null) {
                $node.$component = @{}
            }
            $node = $node.$component
        }
        $leaf = $components[$components.Count - 1]
        
        $node.$($leaf) = $value
        $json | convertto-json -Depth 100 | set-content $file
    }
    catch {
        Write-Error "Failed to set app settings in $file at path '$path': $($_.Exception.Message)"
        throw
    }
}

function test-isSpecialValue($v) {
    if (!$v) { return $false }
    if ($v -is [string]) {
        if ($v.StartsWith("keyvault:")) { return $true }

        foreach ($prefix in Get-ConfigMapValuePrefix) {
            if ($v.StartsWith($prefix)) { return $true }
        }
    }
    return $false
}

function Get-AppsettingsObject(
    [Parameter(Mandatory = $true, ParameterSetName = "file")][string]$file,
    [Parameter(Mandatory = $true, ParameterSetName = "settings")][object]$appSettings,
    [Parameter(Mandatory = $true)]$options
) {
    return Find-ActiveOption -File:$file -AppSettings:$appSettings -Options $options
}

function Find-ActiveOption(
    [Parameter(Mandatory = $true, ParameterSetName = "file")][string]$file,
    [Parameter(Mandatory = $true, ParameterSetName = "settings")][object]$appSettings,
    [Parameter(Mandatory = $true)]$options,
    # Listed user secrets: `user-secrets:` option values then match by their resolved value.
    [hashtable]$secrets
) {
    if (!$appSettings) {
        $appSettings = get-content $file | convertfrom-json -AsHashtable
    }

    $keys = new-object System.Collections.Generic.HashSet[string]
    $active = $null
    $valueObject = [ordered]@{}

    foreach ($optionSet in $options.keys) {
        $option = $options.$optionSet
        $isMatch = $true
        foreach ($key in $option.keys) {
            if ($key.StartsWith("__")) {
                continue
            }
            if (!$valueObject.Contains($key)) {
                $keys.Add($key) | Out-Null
                $currentValue = Get-AppSetting -appSettings:$appSettings -file:$file -path:$key
                $valueObject[$key] = $currentValue
            } else {
                $currentValue = $valueObject[$key]
            }

            $optionValue = $option.$key
            if ($null -ne $secrets -and "$optionValue".StartsWith('user-secrets:')) {
                $optionValue = Resolve-UserSecretReference $optionValue $secrets
                if ($null -eq $optionValue) { $isMatch = $false }
            }

            Write-Verbose "checking key $key=$currentValue"

            # Keep walking after a mismatch so Value still contains every key read from the file.
            if ($isMatch -and $currentValue -is [string] -and $currentValue -ne $optionValue -and !(test-isSpecialValue $optionValue)) {
                Write-Verbose "key $key=$currentValue does not match option '$optionSet' value: $optionValue"
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

function resolve-value($v, [switch]$recurse, [string]$dir, [hashtable]$secrets, [string]$userSecretsId) {
    if (!$v) { return $v }

    if ($v -is [string]) {
        if (!(test-isSpecialValue $v)) { return $v }

        if ($v.StartsWith("keyvault:")) {
            $splits = $v.Substring("keyvault:".Length).Split("/")
            $v = get-keyvaultSecret $splits[0] $splits[1]

            return $v
        }

        foreach ($prefix in Get-ConfigMapValuePrefix) {
            if (-not $v.StartsWith($prefix)) { continue }

            $resolved = Resolve-ConfigMapPluginValue $v -Context @{ Directory = $dir; Secrets = $secrets; UserSecretsId = $userSecretsId }
            if ($null -eq $resolved) { return $v }

            return $resolved
        }
    }
    elseif ($v -is [System.Collections.IDictionary]) {
        if ($recurse) {
            # Same kind of dictionary back: a hashtable stays a hashtable, anything else keeps its order.
            $result = if ($v -is [hashtable]) { @{} } else { [ordered]@{} }
            foreach ($key in @($v.Keys)) {
                $result[$key] = resolve-value $v[$key] -recurse:$recurse -dir $dir -secrets $secrets -userSecretsId $userSecretsId
            }
            return $result
        }
        return $v
    }

    return $v
}

function Get-UnresolvedConfigMapValue {
    <#
    .SYNOPSIS
        Name every value of Resolved that is still null or still a reference, as `key: reference`.
        Only key paths and the original references are named, never a resolved value.
    #>
    param($Original, $Resolved, [string]$Path)

    if ($Original -is [System.Collections.IDictionary]) {
        foreach ($key in @($Original.Keys)) {
            $keyPath = if ($Path) { "$Path.$key" } else { "$key" }
            Get-UnresolvedConfigMapValue -Original $Original[$key] -Resolved $Resolved[$key] -Path $keyPath
        }
        return
    }

    $reference = if (test-isSpecialValue $Original) { "$Original" } else { $null }
    if ($null -ne $Resolved -and -not ($reference -and (test-isSpecialValue $Resolved))) { return }

    $name = if ($Path) { $Path } else { 'value' }
    if ($reference) { "${name}: $reference" } else { "${name}: null" }
}

function Resolve-ConfigMapValue {
    <#
    .SYNOPSIS
        Resolve value references (keyvault: and every plugin prefix, such as bw: and user-secrets:).

    .DESCRIPTION
        A string is resolved when it starts with a registered prefix and returned as is otherwise.
        A hashtable or other dictionary is resolved recursively and returned as the same kind of
        dictionary with the same keys. A reference that cannot be resolved warns and stays as
        the original string (a keyvault: one becomes $null).

        Exported for map scriptblocks, e.g. a build map `exec` that needs a secret:
            $env:API_KEY = Resolve-ConfigMapValue 'bw:my-api/apikey' -Required

    .PARAMETER Value
        A string, or a dictionary of strings / nested dictionaries.

    .PARAMETER Directory
        The .NET project (file or directory) for `user-secrets:` references; also passed to
        plugins as Context.Directory. Defaults to none (dotnet then uses the current directory).

    .PARAMETER UserSecretsId
        Read `user-secrets:` references from this UserSecretsId (`dotnet user-secrets --id`)
        instead of a project; works in repositories without a .NET project.

    .PARAMETER Required
        Throw when any value is still unresolved: null, or still a reference. The error names
        the keys and references that failed, never a secret value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        $Value,
        [string]$Directory,
        [string]$UserSecretsId,
        [switch]$Required
    )

    process {
        if ($null -ne $Value -and $Value -isnot [string] -and $Value -isnot [System.Collections.IDictionary]) {
            throw [System.ArgumentException]::new("Resolve-ConfigMapValue expects a string or a dictionary, not [$($Value.GetType().Name)].", 'Value')
        }

        $resolved = resolve-value $Value -recurse -dir $Directory -userSecretsId $UserSecretsId

        if ($Required) {
            $failed = @(Get-UnresolvedConfigMapValue -Original $Value -Resolved $resolved)
            if ($failed.Count -gt 0) {
                throw "Resolve-ConfigMapValue: $($failed.Count) value(s) could not be resolved: $($failed -join '; ')"
            }
        }

        return $resolved
    }
}

function get-keyvaultSecret($vaultName, $secretName) {
    try {
        $secret = az keyvault secret show --vault-name $vaultName --name $secretName --query value -o tsv 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $secret
        }
        else {
            Write-Warning "Failed to retrieve secret '$secretName' from vault '$vaultName'"
            return $null
        }
    }
    catch {
        Write-Warning "Error accessing Key Vault: $($_.Exception.Message)"
        return $null
    }
}

function get-envsetting($key, $envFile = ".env") {
    if (!(Test-Path $envFile)) {
        return $null
    }
    
    $content = Get-Content $envFile
    foreach ($line in $content) {
        if ($line -match "^$key\s*=\s*(.*)$") {
            return $matches[1].Trim('"')
        }
    }
    return $null
}

function set-envsetting($key, $value, $envFile = ".env") {
    $lines = @()
    $found = $false
    
    if (Test-Path $envFile) {
        # Get-Content returns a string for a one-line file. Force an array so
        # index assignment updates that line instead of concatenating onto it.
        $lines = @(Get-Content $envFile)
    }
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^$key\s*=") {
            $lines[$i] = "$key=$value"
            $found = $true
            break
        }
    }
    
    if (!$found) {
        $lines += "$key=$value"
    }
    
    $lines | Set-Content $envFile
}

function get-envsettingsObject($envFile = ".env") {
    $settings = @{}
    
    if (!(Test-Path $envFile)) {
        return $settings
    }
    
    $content = Get-Content $envFile
    foreach ($line in $content) {
        if ($line -match "^([^=]+)\s*=\s*(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim('"')
            $settings[$key] = $value
        }
    }
    
    return $settings
}

function set-envsettingsObject($settings, $envFile = ".env") {
    $lines = @()
    
    foreach ($key in $settings.Keys) {
        $lines += "$key=$($settings[$key])"
    }
    
    $lines | Set-Content $envFile
}
