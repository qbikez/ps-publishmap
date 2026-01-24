function Invoke-QConf {
    [CmdletBinding()]
    param(
        [ValidateSet("set", "get", "list", "help", "init")]
        $command,

        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    # ipmo configmap
                    $map = $fakeBoundParameters.map
                    $map = $map -is [System.Collections.IDictionary] ? $map : (Resolve-ConfigMap $map -fallback ".configuration.map.ps1" | % { 
                        if ($_ -is [string]) {
                            $loadedMap = . $_
                            $baseDir = Split-Path $_ -Parent
                            Add-BaseDir $loadedMap $baseDir
                        } else {
                            $_
                        }
                    } | Assert-ConfigMap)
                    if (!$map) {
                        return @("init", "help", "list") | ? { $_.startswith($wordToComplete) }
                    }
                    return Get-EntryCompletion $map -language "conf" @PSBoundParameters
                }
                catch {
                    return "ERROR [-entry]: $($_.Exception.Message) $($_.ScriptStackTrace)"
                }
            })]
        $entry = $null,

        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    if ($fakeBoundParameters.command -in @("init", "help")) {
                        return @()
                    }

                    $map = $fakeBoundParameters.map
                    $map = Resolve-ConfigMap $map -fallback ".configuration.map.ps1" | ForEach-Object { 
                        if ($_ -is [string]) {
                            $loadedMap = . $_
                            $baseDir = Split-Path $_ -Parent
                            Add-BaseDir $loadedMap $baseDir
                        } else {
                            $_
                        }
                    } | Assert-ConfigMap
                    $entry = $fakeBoundParameters.entry
                    $entry = Get-MapEntry $map $entry
                    if (!$entry) {
                        throw "entry '$entry' not found"
                    }
                    $options = Get-CompletionList $entry -listKey "options" -language "conf" -maxDepth 1
                    return $options.Keys | ? { $_.startswith($wordToComplete) }
                }
                catch {
                    return "ERROR [-value]: $($_.Exception.Message) $($_.ScriptStackTrace)"
                }
            })]
        $value = $null,
        $map = "./.configuration.map.ps1"
    )

    ## we need dynamic parameters for commands that have custom parameter list
    ## this assumes that -entry and -command are already provided
    dynamicparam {
        # ipmo configmap
        try {
            if ( !$entry) {
                return @()
            }
            $map = Resolve-ConfigMap $map -fallback ".configuration.map.ps1" | ForEach-Object { 
                if ($_ -is [string]) {
                    $loadedMap = . $_
                    $baseDir = Split-Path $_ -Parent
                    Add-BaseDir $loadedMap $baseDir
                } else {
                    $_
                }
            } | Assert-ConfigMap
            $skip = switch ($command) {
                "set" { 3 }
                default { 0 }
            }

            return Get-EntryDynamicParam $map "$entry.$command" -skip $skip -bound $PSBoundParameters
        }
        catch {
            return "ERROR [dynamic]: $($_.Exception.Message) $($_.ScriptStackTrace)"
        }
    }

    process {
        if ($command -eq "help") {
            Write-Host "QCONF"
            Write-Host "A command line tool to manage configuration maps"
            Write-Host ""
            Write-Host "Usage:"
            Write-Host "qconf -entry <entry> -command <command> -value <value>"
            return
        }
        if ($command -eq "init") {
            if (!$map) { $map = "./.configuration.map.ps1" }
            if ($map -is [string]) {
                if ((Test-Path $map)) {
                    throw "map file '$map' already exists"
                }
            }
            else {
                throw "Map appears to be an object, not a file"
            }

            Initialize-ConfigMap -file $map

            return
        }

        $map = $map -is [System.Collections.IDictionary] ? $map : (Resolve-ConfigMap $map | ForEach-Object { 
            if ($_ -is [string]) {
                $loadedMap = . $_
                $baseDir = Split-Path $_ -Parent
                Add-BaseDir $loadedMap $baseDir
            } else {
                $_
            }
        } | Assert-ConfigMap)

        if (-not $entry -and -not $command) {
            Write-MapHelp -map $map -invocation $MyInvocation -language "conf"
            return
        }

        if ($command -and -not $entry) {

        }

        Write-Verbose "entry=$entry command=$command"


        switch ($command) {
            "set" {
                $subEntry = $map.$entry
                if (!$subEntry) {
                    throw "entry '$entry' not found"
                }

                $optionKey = $value
                $options = Get-CompletionList $subEntry -listKey "options" -language "conf" -maxDepth 1
                $optionValue = $options.$optionKey

                $bound = $PSBoundParameters
                $bound.key = $optionKey
                $bound.value = $optionValue
                Invoke-Set $subEntry -ordered "", $optionValue, $optionKey -bound $bound
            }
            "get" {
                $entries = $entry
                if (!$entries) {
                    # not passing -listKey "options" here, as we don't want to expand options - we just need top-level keys
                    $entries = (Get-CompletionList $map -language "conf").Keys
                }

                foreach ($entry in @($entries)) {
                    try {
                        $subEntry = $map.$entry

                        $options = Get-CompletionList $subEntry -listKey "options" -language "conf" -maxDepth 1

                        $bound = $PSBoundParameters
                        $bound.options = $options

                        $value = Invoke-Get $subEntry -bound $bound

                        $result = ConvertTo-MapResult $value $entry $subEntry $options
                        $result | Write-Output
                    }
                    catch {
                        if ($env:QCONF_DEBUG -eq "1") {
                            throw $_
                        }
                        Write-Error "Error getting value for entry '$entry': $($_.Exception.Message)"
                    }
                }
            }
            default {
                throw "command '$command' not supported"
            }
        }

    }
}

function ConvertTo-MapResult($value, $entryName, $entry, $options, $validate = $true) {
    $result = $null
    if ($value -is [Hashtable]) {
        $hash = @{
            Path = "$entryName/$subPath"
        }
        $hash += $value

        $result = $hash
    }
    else {
        $result = @{
            Path  = "$entryName/$subPath"
            Value = $value
        }
    }

    if (!$result.Active) {
        $result.Active = $options.keys | where { $options.$_ -eq $value }
    }
    $result.Options = $options.keys

    $isvalid = "?"
    if ($validate -and $entry.validate) {
        if (!$result.Active) {
            Write-Warning "no active option found for $entryName/$subPath"
            $isvalid = $null
        }
        else {
            $optionvalue = $options.$($result.Active)
            $isvalid = Invoke-EntryCommand $entry validate -ordered @($path, $optionvalue, $result.Active)
        }
    }

    $result = [PSCustomObject]@{
        Path    = $result.Path
        Value   = $result.Value
        Active  = $result.Active
        Options = $result.Options
        IsValid = $isvalid
    }

    return $result
}

Set-Alias -Name "qconf" -Value "Invoke-QConf" -Force
