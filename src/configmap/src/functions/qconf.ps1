function Invoke-QConf {
    [CmdletBinding()]
    param(
        [ValidateSet("set", "get", "list", "help", "init")]
        $command,

        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    $mapPath = if ($fakeBoundParameters.map) { $fakeBoundParameters.map } else { "./.configuration.map.ps1" }
                    $localMapExists = Test-Path $mapPath

                    $map = Import-ConfigMap -Map $fakeBoundParameters.map -Fallback ".configuration.map.ps1" -ErrorAction Ignore | Assert-ConfigMap

                    $completions = Get-EntryCompletion $map -language "conf" @PSBoundParameters
                    # Include !init if no local map file exists
                    if (!$localMapExists) {
                        $completions = @("!init" | ? { $_.startswith($wordToComplete) }) + $completions
                    }
                    return $completions
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

                    $map = Import-ConfigMap -Map $fakeBoundParameters.map -Fallback ".configuration.map.ps1" | Assert-ConfigMap
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
            $map = Import-ConfigMap -Map $map -Fallback ".configuration.map.ps1" | Assert-ConfigMap
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
        if ($entry -eq "!init") {
            # Only check current directory - create new map regardless of parent configs
            if (Test-Path $map) {
                throw "map file '$map' already exists"
            }
            Initialize-ConfigMap -file $map
            return
        }

        $map = Import-ConfigMap -Map $map | Assert-ConfigMap

        if (-not $entry -and -not $command) {
            Write-MapHelp -map $map -invocation $MyInvocation -language "conf"
            return
        }

        if ($command -and -not $entry) {

        }

        Write-Verbose "entry=$entry command=$command"
        $operationContext = New-ConfigMapOperationContext

        switch ($command) {
            "set" {
                $subEntry = Get-MapEntry $map $entry -language "conf" -OperationContext $operationContext
                if (!$subEntry) {
                    throw "Entry '$entry' not found. Run 'qconf list' to see all available entries."
                }

                $optionKey = $value
                $options = Get-CompletionList $subEntry -listKey "options" -language "conf" -maxDepth 1
                $optionValue = $options.$optionKey

                $bound = $PSBoundParameters
                $bound.key = $optionKey
                $bound.value = $optionValue
                Invoke-WithEntrySettings -Map $map -EntryKey "$entry" -Entry $subEntry -OperationContext $operationContext -ScriptBlock {
                    Invoke-Set $subEntry -ordered @("", $optionValue, $optionKey) -bound $bound
                }
            }
            "get" {
                $entries = $entry
                if (!$entries) {
                    # not passing -listKey "options" here, as we don't want to expand options - we just need top-level keys
                    $entries = (Get-CompletionList $map -language "conf").Keys
                }

                foreach ($entryName in @($entries)) {
                    $subEntry = Get-MapEntry $map $entryName -language "conf" -OperationContext $operationContext
                    $bound = @{}
                    foreach ($boundKey in $PSBoundParameters.Keys) {
                        $bound[$boundKey] = $PSBoundParameters[$boundKey]
                    }

                    Invoke-WithEntrySettings -Map $map -EntryKey "$entryName" -Entry $subEntry -OperationContext $operationContext -ScriptBlock {
                        try {
                            if (!$subEntry) {
                                throw "Entry '$entryName' not found. Run 'qconf list' to see all available entries."
                            }

                            $options = Get-CompletionList $subEntry -listKey "options" -language "conf" -maxDepth 1
                            $bound.options = $options

                            $value = Invoke-Get $subEntry -bound $bound

                            $result = ConvertTo-MapResult $value $entryName $subEntry $options
                            $result | Write-Output
                        }
                        catch {
                            if ((Get-ConfigMapSetting -Name Debug) -eq '1') {
                                throw $_
                            }
                            Write-Error "Error getting value for entry '$entryName': $($_.Exception.Message)"
                        }
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
