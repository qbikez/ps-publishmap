#Requires -Version 7.0

# Legacy helpers removed from configmap/.config-utils.ps1 because nothing in the module,
# tests, docs or sample maps calls them. Nothing loads this file: it is kept for reference
# only. To use a helper, copy it into your own map or utils file and dot-source that.

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

function Get-SSOToken($env) {
    if (!(which gstln-login)) {
        npm install -g git+https://dev.azure.com/guestlinelabs/Mandalore/_git/gstln-login
    }

    $token = gstln-login -env $env | ConvertFrom-Json
    return $token.accessToken
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
                    OptionKey   = $optionSet
                    Result      = $result
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
                OptionKey   = $optionSet
                Result      = $result
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
