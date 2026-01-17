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

function get-appsettings([Parameter(Mandatory = $true)]$file, $path = "") {
    $json = get-content $file | convertfrom-json

    $components = $path.split(":")
    $node = $json
    foreach ($component in $components) {
        $node = $node.$component
    }

    return $node
}

function set-appsettings(
    [Parameter(Mandatory = $true)] $file,
    [Parameter(Mandatory = $true)] $path,
    [Parameter(Mandatory = $true)] $value
) {
    $json = get-content $file | convertfrom-json -AsHashtable

    $components = $path.split(":")
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

function test-isSpecialValue($v) {
    return $v -and $v -is [string] -and ($v.StartsWith("user-secrets:") -or $v.StartsWith("keyvault:"));
}
function resolve-value($v) {
    $v = $value.$key
    if (!(test-isSpecialValue $v)) { return $v }

    if ($v -and $v -is [string] -and $v.StartsWith("user-secrets:")) {
        $secretName = $v.Substring("user-secrets:".Length)
        $secrets = dotnet user-secrets -p $dir list --json | ? { !$_.StartsWith("//") } | ConvertFrom-Json -AsHashtable
        if ($LASTEXITCODE -ne 0) {
            write-warning "cannot set '$secretName': failed to list user secrets for project in '$dir'. Do you have 'dotnet user-secrets' installed?"
            continue
        }
        if (!$secrets.ContainsKey($secretName)) {
            write-warning "secret '$secretName' not found in user secrets. Please run 'dotnet user-secrets -p $dir set $secretName <value>' to set the secret."
            continue
        }
        $v = $secrets[$secretName]
    }

    if ($v -and $v -is [string] -and $v.StartsWith("keyvault:")) {
        $splits = $v.Substring("keyvault:".Length).Split("/")
        $v = get-keyvaultSecret $splits[0] $splits[1]
    }

    return $v
}

function set-appsettingsobject(
    [Parameter(Mandatory = $true)]$file, 
    [Parameter(Mandatory = $true)]$value
) {
    $dir = split-path $file
    foreach ($key in $value.keys) {
        if ($key.StartsWith("__")) {
            continue
        }

        $v = resolve-value $value.$key

        set-appsettings $file -path $key -value $v
    }
}

function get-appsettingsObject(
    [Parameter(Mandatory = $true)][string]$file, 
    [Parameter(Mandatory = $true)]$options
) {
    foreach ($optionSet in $options.keys) {
        write-verbose "checking '$optionSet'"
        $option = $options[$optionSet]
        $isMatch = $true
        foreach ($key in $option.keys) {
            Write-Verbose "getting key $key=$v"
            $v = get-appsettings $file $key
            if ($v -is [string] -and $v -ne $option[$key] -and !(test-isSpecialValue $option[$key])) {
                Write-Verbose "key $key=$v does not match options[$optionSet].$key=$($option[$key])"
                $isMatch = $false
                # if any of the keys do not match, break out of the loop
                break
            }
        }
        if ($isMatch) {
            return @{ value = $optionSet; Active = $optionSet }
        }
    }
    
    return @{ value = "?"; }
}

function test-azureAccount($value) {
    $account = az account show | ConvertFrom-Json
    $targetSubscription = $value["__AzureSubscription"];
    if (!$targetSubscription) {
        write-warning "no '__AzureSubscription' subscription specified in $($value | ConvertTo-Json)"
        return $true
    }
    $targetTenant = $value["__AzureTenant"]

    if ($account) {
        if (($account.name -eq $targetSubscription -or $account.id -eq $targetSubscription)) {
            write-host "✅ active azure account: $($account.name) [$($account.id)]"
            write-host "   active tenant:        $($account.tenantId)"
            return $true
        }
        else {
            write-host "❌ active azure account: $($account.name) [$($account.id)] does not match target subscription '$targetSubscription'"
        }
    }
    else {
        write-host "no active azure account"
    }

    return $false
}
function set-azureAccount($value) {
    $targetSubscription = $value["__AzureSubscription"];
    $targetTenant = $value["__AzureTenant"]

    if (test-azureAccount $value) {
        return
    }

    Write-Host "Logging into azure..."
    $a = @()
    if ($targetTenant) {
        $a += "--tenant", $targetTenant
    }
    az login @a
    Write-Host "Selecting subscription $targetSubscription..."
    az account set --subscription $targetSubscription

}

function get-dockerContainer(
    [Parameter(Mandatory = $false)] $displayName, 
    [Parameter(ParameterSetName = "port", Mandatory = $true)] $port, 
    [Parameter(ParameterSetName = "name", Mandatory = $true)] $name 
) {
    $dockerVersionStr = docker -v
    $m = $dockerVersionStr -match "[0-9]+\.[0-9]+\.[0-9]+"
    $dockerVersion = [version]::Parse($matches[0])

    if ($dockerVersion.Major -lt 24) {
        return @{ Value = "? (Docker version >=24 required)" }
    }
    
    $containers = docker ps -a --format json | convertfrom-json 
    if ($port -ne $null) {
        $container = $containers | ? { $_.Ports.contains([string]$port) }
    }
    elseif ($name -ne $null) {
        if ($name.StartsWith("/")) {
            $regexp = [regex]::new($name.Trim("/"))
            $container = $containers | ? { $regexp.IsMatch($_.Image) -or $regexp.IsMatch($_.Names) }
        }
        else {
            $container = $containers | ? { $_.Image.StartsWith($name) -or $_.Names.StartsWith($name) }
        }
    }
    
    write-verbose "== all containers: =="
    docker -v | write-verbose
    docker compose version | write-verbose
    $containers | convertto-json | write-verbose
    write-verbose "== containers END =="

    return $container
}
function test-dockerContainer(
    [Parameter(Mandatory = $false)] $displayName, 
    [Parameter(ParameterSetName = "port", Mandatory = $true)] $port, 
    [Parameter(ParameterSetName = "name", Mandatory = $true)] $name) {
    $container = $null
    if ($port) { 
        $container = get-dockerContainer -displayName $displayName -port $port
        if (!$container) {
            write-host "❌ $displayName container at port $port not found"
            return $false
        }
    }
    if ($name) { 
        $container = get-dockerContainer -displayName $displayName -name $name
        if (!$container) {
            write-host "❌ $displayName container matching name '$name' not found"
            return $false
        }
    }

    
    $isvalid = $container -and $container.state -eq "running"

    if ($isvalid ) { write-host "✅ $displayName running" }
    else { write-host "❌ $displayName not running" }

    return $isvalid
}

function test-dockerDb($containerName, $dbName = "rls_lagerman") {
    write-verbose "checking if db is running..."
    $container = get-dockerContainer -name $containerName
    if (!$container) {
        throw "no containers found with name matching '$containerName'"
    }
    if (@($container).Length -gt 1) {
        throw "multiple containers found with name matching '$containerName'"
    }

    $containerName = $container.Names
    write-verbose "checking sql connection to $containerName..."
    
    $retries = 5
    $backoff = 5

    for ($i = $retries; $i -ge 0; $i++) {
        $result = docker exec $containerName "/opt/mssql-tools/bin/sqlcmd" -S localhost -U sa -P '12345678!aA#' -Q "print 'select from inisettings'; use [$dbName]; select top 10 * from inisitesettings;"
        $result

        if ($lastExitCode -eq 0 -and $result[0].StartsWith("select from inisettings")) {
            write-verbose "DB is running"
            break
        }
        else {
            write-verbose "DB is not running"
            if ($i -eq 0) {
                return $false
            }
            write-verbose "retrying in $backoff s..."
            Start-Sleep -Seconds $backoff
        }
    }

    write-verbose "DONE exitCode=$LastExitCode"
    return $true
}

function get-envsetting($file, $path) {
    if (!(test-path $file)) {
        return $null
    }
    $env = get-content $file | ConvertFrom-StringData
    return $env.$path
}

function set-envsetting($file, $path, $value) {
    $envData = @{}
    if (test-path $file) {
        $envData = get-content $file | ConvertFrom-StringData
    }
    $hash = [ordered]@{}
    $envData.keys | % {
        $hash[$_] = $envData.$_
    }
    $hash[$path] = $value
    $hash.GetEnumerator() | % {
        "$($_.key)=$($_.value)"
    } | Out-File $file
}

function set-envsettingsObject($file, $path, $value) {
    $dir = split-path $file
    foreach ($key in $value.keys) {
        if ($key.StartsWith("__")) {
            continue
        }

        $v = resolve-value $value.$key
        
        set-envsetting $file -path $key -value $v
    }   
}

function get-envsettingsObject(
    [Parameter(Mandatory = $true)][string]$file, 
    [Parameter(Mandatory = $true)]$options
) {
    if (!(test-path $file)) {
        return @{ value = $null; Active = $null }
    }
    $value = get-content $file | ConvertFrom-StringData
    
    foreach ($optionSet in $options.keys) {
        $option = $options.$optionSet
        $isMatch = $true
        foreach ($key in $option.keys) {
            $v = $value.key
            Write-Verbose "getting key $key=$v"
            if ($v -is [string] -and $v -ne $option.$key -and !(test-isSpecialValue $option.$key)) {
                Write-Verbose "key $key=$v does not match $option.$key"
                $isMatch = $false
                break
            }
        }
        if ($isMatch) {
            return @{ value = $value; Active = $optionSet }
        }
    }
    
    return @{ value = $value; Active = $null }
}

function get-keyvaultSecret($keyvault, $secret) {
    $secret = az keyvault secret show --vault-name $keyvault --name $secret | ConvertFrom-Json
    return $secret.value
}

Function Create-JWT(
    [Parameter(Mandatory = $true)]$headers,
    [Parameter(Mandatory = $true)]$payload,
    [Parameter(Mandatory = $true)]$secret
) {


    $headersJson = $headers | ConvertTo-Json -Compress
    $payloadJson = $payload | ConvertTo-Json -Compress
    $headersEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($headersJson), [Base64FormattingOptions]::None).TrimEnd('=')
    $payloadEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($payloadJson), [Base64FormattingOptions]::None).TrimEnd('=')

    $content = "$($headersEncoded).$($payloadEncoded)"

    $hmacsha = New-Object System.Security.Cryptography.HMACSHA256  
    $hmacsha.key = [Text.Encoding]::UTF8.GetBytes($secret)
    $bytesToSign = [Text.Encoding]::UTF8.GetBytes($content)
    $signatureByte = $hmacsha.ComputeHash($bytesToSign)

    $signature = [System.Convert]::ToBase64String($signatureByte, [Base64FormattingOptions]::None).Replace('+', '-').Replace('/', '_').Replace("=", "").TrimEnd('=')

    $jwt = "$($headersEncoded).$($payloadEncoded).$($signature)"

    return $jwt

}

function get-xmlconfig($file, $path) {
    if (!(test-path $file)) {
        return $null
    }
    $config = [xml](get-content $file)

    $splits = $path.Split("/")
    $current = $config
    $currentPath = ""
    foreach ($split in $splits) {
        if ($current[$split] -eq $null) {
            throw "Could not find $split in $currentPath"
        }
        $current = $current[$split]
        $currentPath += "/$split"
       
    }
    
    return $current.InnerXml
}

function set-xmlconfig($file, $path, $value) {
    $fullPath = [System.IO.Path]::GetFullPath($file)
    if ((test-path $fullPath)) {
        $config = [xml](get-content $fullPath)
    }
    else {
        $config = [xml]""
    }

    $splits = $path.Split("/")
    $current = $config
    $currentPath = ""
    foreach ($split in $splits) {
        if ($current[$split] -eq $null) {
            $current.AppendChild($config.CreateElement($split))
        }
        $current = $current[$split]
        $currentPath += "/$split"
       
    }
    
    $current.InnerXml = $value
    
    $config.Save($fullPath)
}

function test-httpurl($url) {
    try {
        $result = Invoke-WebRequest -Uri $url -Method Get -UseBasicParsing -ErrorAction SilentlyContinue
        return ($result.statuscode -eq 200)

    }
    catch {
        if ($_.Exception.StatusCode -eq 404) {
            # 404 means the service is there and responding, so treat it as success
            return $true
        }
        return $false
    }
}
