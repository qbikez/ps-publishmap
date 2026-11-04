#Requires -Version 7.0

# Helpers used by the qconf entry types (appsettings, dotenv and user-secrets templates).
# Map scriptblocks run in module scope, so these names are also part of the documented
# map contract (skills/qbuild-templates/SKILL.md, samples/dotenv). Keep the names.

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
        return $v.StartsWith("user-secrets:") -or $v.StartsWith("keyvault:")
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
    [Parameter(Mandatory = $true)]$options
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

function resolve-value($v, [switch]$recurse, [string]$dir, [hashtable]$secrets) {
    if (!$v) { return $v }

    if ($v -is [string]) {
        if (!(test-isSpecialValue $v)) { return $v }

        if ($v.StartsWith("user-secrets:")) {
            $secretName = $v.Substring("user-secrets:".Length)

            if ($null -eq $secrets) {
                $secrets = get-user-secrets $dir
                if ($LASTEXITCODE -ne 0) {
                    write-warning "cannot set '$secretName': failed to list user secrets for project in '$dir'. Do you have 'dotnet user-secrets' installed?"
                    return $v
                }
            }
            if (!$secrets.ContainsKey($secretName)) {
                write-warning "secret '$secretName' not found in user secrets. Please run 'dotnet user-secrets -p $dir set $secretName <value>' to set the secret."
                return $v
            }
            $v = $secrets[$secretName]

            return $v
        }

        if ($v.StartsWith("keyvault:")) {
            $splits = $v.Substring("keyvault:".Length).Split("/")
            $v = get-keyvaultSecret $splits[0] $splits[1]

            return $v
        }
    }
    elseif ($v -is [hashtable]) {
        if ($recurse) {
            $result = [ordered]@{}
            foreach ($key in $v.keys) {
                $result[$key] = resolve-value $v[$key] -recurse:$recurse -dir $dir -secrets $secrets
            }
            return $result
        }
        return $v
    }

    return $v
}

function get-user-secrets($dir) {
    $secrets = @{}
    
    try {
        $output = dotnet user-secrets list --project $dir 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $secrets
        }
        
        foreach ($line in $output) {
            if ($line -match "^(.+?)\s*=\s*(.*)$") {
                $secrets[$matches[1]] = $matches[2]
            }
        }
    }
    catch {
        Write-Warning "Failed to retrieve user secrets: $($_.Exception.Message)"
    }
    
    return $secrets
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
