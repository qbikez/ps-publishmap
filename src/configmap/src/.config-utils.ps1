#Requires -Version 7.0

function replace-values($object, $values) {
    $result = [ordered]@{}
    foreach ($key in $object.keys) {
        $value = $object.$key
        if ($value -is [string] -and $values.$value) {
            $result.$key = $values.$value
        }
        elseif ($value -is [hashtable]) {
            $result.$key = replace-values $value $values
        }
        else {
            $result.$key = $value
        }
    }

    return $result
}

function inherit-base($base, $module) {
    write-verbose "inheriting base module $($base.name) for $($module.name)"
    foreach ($key in $base.args.keys) {
        if ($module.inherit.args[$key] -eq $null) {
            $module.inherit.args[$key] = $base.args[$key]
        }
    }

    $module.get = {
        param($path, $options)
        Invoke-Command -ScriptBlock $base.get -ArgumentList @($module, $path, $options)
    }.GetNewClosure()

    $module.set = {
        param($path, $value, $key, $additionalOpts)

        . $PSScriptRoot/.config-utils.ps1
        $value = replace-values $module.inherit.template $value
        Invoke-Command -ScriptBlock $base.set -ArgumentList @($module, $path, $value, $key, $additionalOpts)
    }.GetNewClosure()
    $module.options = $base.options
    $module.validate = $base.validate

    return $module
}

function make-alias($moduleName, $path = $null, $workingDir = $null, $hooks) {
    if ($workingDir -eq $null) {
        $workingDir = $PSScriptRoot
    }
    $modulePath = $moduleName
    if ($path -ne $null) {
        $modulePath = "$moduleName/$path"
    }
    return @{
        get      = {
            param($path, $options)
            pushd $workingDir
            try {
                $r = & .\configure.ps1 -command get -module $modulePath -porcelain
                if ($hooks -and $hooks.get) {
                    $subResult = & $hooks.get -path $path -options $options
                    if ($subResult) {
                        foreach ($key in $subResult.keys) {
                            $r.$key = $subResult[$key]
                        }
                    }
                }

                return @{ Value = $r.Value; Active = $r.Active; IsValid = $r.IsValid }
            }
            finally {
                popd
            }
        }.GetNewClosure()
        set      = {
            param($path, $v, $optName)
            
            $r = $null
            pushd $workingDir
            try {
                
                . .\.configuration.map.ps1
                $module = $modules.$moduleName
                $moduleCommand = $module.set
                $r = Invoke-Command -ScriptBlock $moduleCommand -ArgumentList @($path, $v, $optName)
            }
            finally {
                popd
            }
            if ($hooks -and $hooks.set) {
                $subResult = & $hooks.set -path $path -value $v -key $optName
            }
            return $r
        }.GetNewClosure()
        validate = {
            param($path, $v, $optName)
            
            pushd $workingDir
            try {
                $r = & .\configure.ps1 -command validate -module $modulePath -porcelain

                return $r.IsValid
            }
            finally {
                popd
            }
        }.GetNewClosure()
        options  = {
            param($path)
            pushd $workingDir
            try {
                $r = & .\configure.ps1 -command options -module $modulePath -porcelain

                if ($hooks -and $hooks.options) {
                    $subResult = & $hooks.options -path $path -options $r
                    if ($subResult) {
                        return $subResult
                    }
                }
                
                return $r
            }
            finally {
                popd
            }
        }.GetNewClosure()
    }
}

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

            if ($currentValue -is [string] -and $currentValue -ne $optionValue -and !(test-isSpecialValue $optionValue)) {
                Write-Verbose "key $key=$currentValue does not match option '$optionSet' value: $optionValue"
                $isMatch = $false
                break
            }
        }
        if ($isMatch) {
            $active = $optionSet
            break
        }
    }

    return @{ Value = $valueObject; Active = $active }
}

function resolve-value($v, [switch]$recurse, [string]$dir) {
    if (!$v) { return $v }

    if ($v -is [string]) {
        if (!(test-isSpecialValue $v)) { return $v }

        if ($v.StartsWith("user-secrets:")) {
            $secretName = $v.Substring("user-secrets:".Length)
            
            $secrets = get-user-secrets $dir
            if ($LASTEXITCODE -ne 0) {
                write-warning "cannot set '$secretName': failed to list user secrets for project in '$dir'. Do you have 'dotnet user-secrets' installed?"
                return $v
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
                $result[$key] = resolve-value $v[$key] -recurse:$recurse -dir $dir
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

function Get-SSOToken($env) {
    if (!(which gstln-login)) {
        npm install -g git+https://dev.azure.com/guestlinelabs/Mandalore/_git/gstln-login
    }

    $token = gstln-login -env $env | ConvertFrom-Json
    return $token.accessToken
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
        $lines = Get-Content $envFile
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

function execute-sql($connectionString, $query) {
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()
        
        $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
        $result = $command.ExecuteScalar()
        
        $connection.Close()
        return $result
    }
    catch {
        Write-Error "SQL execution failed: $($_.Exception.Message)"
        throw
    }
}

function Create-JWT($header, $payload, $secret) {
    $headerJson = $header | ConvertTo-Json -Compress
    $payloadJson = $payload | ConvertTo-Json -Compress
    
    $headerEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($headerJson)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $payloadEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payloadJson)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    
    $toSign = "$headerEncoded.$payloadEncoded"
    $secretBytes = [Text.Encoding]::UTF8.GetBytes($secret)
    $toSignBytes = [Text.Encoding]::UTF8.GetBytes($toSign)
    
    $hmac = New-Object System.Security.Cryptography.HMACSHA256($secretBytes)
    $signature = $hmac.ComputeHash($toSignBytes)
    $signatureEncoded = [Convert]::ToBase64String($signature).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    
    return "$toSign.$signatureEncoded"
}

function test-httpUrl($url) {
    try {
        $response = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 10 -UseBasicParsing
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function get-xmlconfiguration($file, $path) {
    if (!(Test-Path $file)) {
        throw "XML file not found: $file"
    }
    
    [xml]$xml = Get-Content $file
    
    if ([System.IO.Path]::IsPathRooted($path)) {
        $xpath = $path
    } else {
        $xpath = "//$path"
    }
    
    $node = $xml.SelectSingleNode($xpath)
    if ($node) {
        if ($node.InnerText) {
            return $node.InnerText
        } else {
            return $node.OuterXml
        }
    }
    
    return $null
}

function set-xmlconfiguration($file, $path, $value) {
    if (!(Test-Path $file)) {
        throw "XML file not found: $file"
    }
    
    [xml]$xml = Get-Content $file
    
    if ([System.IO.Path]::IsPathRooted($path)) {
        $xpath = $path
    } else {
        $xpath = "//$path"
    }
    
    $node = $xml.SelectSingleNode($xpath)
    if ($node) {
        $node.InnerText = $value
        $xml.Save($file)
    } else {
        throw "XPath not found: $path"
    }
}

function compare-optionsWithValues(
    [Parameter(Mandatory = $true)]$options,
    [Parameter(Mandatory = $true)]$getValueFunction,
    [string] $path = ""
) {
    foreach ($optionSet in $options.keys) {    
        $option = $options.$optionSet
        if ($path) {
            $option = $option.$path
        }

        $matchDict = @{}
        foreach ($key in $option.keys) {
            $actualValue = & $getValueFunction $key
            $optionValue = $option.$key

             $result = $null
            if ($actualValue -isnot [string]) {
                $result = "skipped:not a string"
            }
            elseif (test-isSpecialValue $optionValue) {
                $result = "skipped:special value"
            }

            if ($result -ne $null) {
                $matchDict[$key] = @{
                    OptionKey = $optionSet
                    Result = $result
                    OptionValue = $optionValue
                    ActualValue = $actualValue
                }
                continue
            }
           

            if ($actualValue -eq $optionValue) {
                $result = "match"
            } else {
                $result = "not-match"
            }

            $matchDict[$key] = @{
                OptionKey = $optionSet
                Result = $result
                OptionValue = $optionValue
                ActualValue = $actualValue
            }
        }

        $notMatch = $matchDict.values | ? { $_.Result -eq "not-match" }
        $skipped = $matchDict.values | ? { $_.Result -eq "skipped" }
        $match = $matchDict.values | ? { $_.Result -eq "match" }

        if ($notMatch.Count -eq 0 -and $match.Count -gt 0) {
            return @{ Active = $optionSet }
        } else {
            $matchDict | ConvertTo-Json | write-verbose
        }
    }
    
    return @{ Active = $null }
}

function get-dockerContainerVersion($containerName) {
    try {
        $output = docker ps --filter "name=$containerName" --format "{{.Image}}" 2>$null
        if ($LASTEXITCODE -eq 0 -and $output) {
            if ($output -match ":(.+)$") {
                return $matches[1]
            }
            return "latest"
        }
        return $null
    }
    catch {
        return $null
    }
}

function start-dockerContainer($containerName, $imageName, $ports = @(), $environment = @()) {
    try {
        $existing = docker ps -a --filter "name=$containerName" --format "{{.Names}}" 2>$null
        if ($existing -eq $containerName) {
            $status = docker ps --filter "name=$containerName" --format "{{.Status}}" 2>$null
            if (!$status) {
                Write-Host "Starting existing container: $containerName"
                docker start $containerName | Out-Null
            }
            return
        }
        
        $runArgs = @("run", "-d", "--name", $containerName)
        
        foreach ($port in $ports) {
            $runArgs += "-p"
            $runArgs += $port
        }
        
        foreach ($env in $environment) {
            $runArgs += "-e"
            $runArgs += $env
        }
        
        $runArgs += $imageName
        
        Write-Host "Creating and starting container: $containerName"
        & docker @runArgs | Out-Null
    }
    catch {
        Write-Error "Failed to start Docker container '$containerName': $($_.Exception.Message)"
        throw
    }
}