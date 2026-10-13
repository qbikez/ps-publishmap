function Invoke-QConf {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
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
        [string]$value = $null,

        [Parameter(DontShow)]
        [string]$Word,
        [Parameter(DontShow)]
        [switch]$Params,

        $map = "./.configuration.map.ps1",

        [Parameter(ValueFromRemainingArguments = $true, DontShow = $true)]
        [string[]]$RemainingArguments
    )

    dynamicparam {
        try {
            $verbs = @('set', 'get', 'list', 'help', 'init', '!init', '!complete')
            $dynamicEntry = if ($entry) {
                $entry
            }
            elseif ($command -and $command -notin $verbs) {
                [string]$command
            }
            else {
                $null
            }
            if (-not $dynamicEntry) { return }

            $map = Import-ConfigMap -Map $map -Fallback ".configuration.map.ps1" | Assert-ConfigMap
            $operation = if ($command -eq 'set' -or $PSBoundParameters.ContainsKey('value')) { 'set' } else { 'get' }
            $skip = if ($operation -eq 'set') { 3 } else { 0 }

            return Get-EntryDynamicParam $map "$dynamicEntry.$operation" -skip $skip -bound $PSBoundParameters
        }
        catch {
            return "ERROR [dynamic]: $($_.Exception.Message) $($_.ScriptStackTrace)"
        }
    }

    process {
        $verbs = @('set', 'get', 'list', 'help', 'init', '!init', '!complete')
        $verb = $null
        $confEntry = $entry

        if ($command -in $verbs) {
            $verb = [string]$command
        }
        elseif ($command) {
            if (-not $confEntry) {
                $confEntry = [string]$command
            }
        }

        $operationArgs = @($RemainingArguments | Where-Object { $null -ne $_ -and "$_" -ne '' })
        if (-not $verb -and $confEntry -and $operationArgs.Count -gt 0) {
            switch ($operationArgs[0]) {
                'get' {
                    $verb = 'get'
                    $operationArgs = @($operationArgs | Select-Object -Skip 1)
                }
                'set' {
                    $verb = 'set'
                    if (-not $PSBoundParameters.ContainsKey('value') -and $operationArgs.Count -gt 1) {
                        $value = $operationArgs[1]
                    }
                    $operationArgs = @($operationArgs | Select-Object -Skip 2)
                }
            }
        }

        if (-not $verb -and $confEntry) {
            $verb = if ($PSBoundParameters.ContainsKey('value')) { 'set' } else { 'get' }
        }

        if ($verb -eq "help") {
            Write-Host "QCONF"
            Write-Host "A command line tool to manage configuration maps"
            Write-Host ""
            Write-Host "Usage:"
            Write-Host "qconf <entry> get"
            Write-Host "qconf <entry> set <option>"
            Write-Host "qconf <entry> [-value <option>]  # shorthand"
            Write-Host "qconf list [<entry>]"
            return
        }
        if ($verb -in @('init', '!init') -or $confEntry -eq "!init") {
            # Only check current directory - create new map regardless of parent configs
            if (Test-Path $map) {
                throw "map file '$map' already exists"
            }
            Initialize-ConfigMap -file $map
            return
        }

        if ($verb -eq '!complete') {
            $completeMap = Import-ConfigMap -Map $map -Fallback ".configuration.map.ps1" -ErrorAction Ignore
            if (-not $completeMap) {
                $global:LASTEXITCODE = 2
                return
            }

            $mode = if ($Params) { 'params' } elseif ($PSBoundParameters.ContainsKey('Word')) { 'word' } else { $null }
            $completeEntry = $confEntry
            $tokens = @($RemainingArguments | Where-Object { $null -ne $_ -and "$_" -ne '' })
            for ($index = 0; $index -lt $tokens.Count; $index++) {
                switch ($tokens[$index]) {
                    '-params' { $mode = 'params' }
                    '-word' {
                        if ($index + 1 -lt $tokens.Count) {
                            $Word = $tokens[++$index]
                            $mode = 'word'
                        }
                    }
                    '-entry' {
                        if ($index + 1 -lt $tokens.Count) {
                            $completeEntry = $tokens[++$index]
                        }
                    }
                    default {
                        if (-not $completeEntry) { $completeEntry = $tokens[$index] }
                    }
                }
            }

            if ($mode -eq 'params' -and $completeEntry) {
                $names = [System.Collections.Generic.List[string]]::new()
                $names.Add('value') | Out-Null
                $dynamic = Get-EntryDynamicParam $completeMap "$completeEntry.set" -skip 3 -bound @{}
                if ($dynamic) {
                    foreach ($name in @($dynamic.Keys)) {
                        if (-not $names.Contains($name)) { $names.Add($name) | Out-Null }
                    }
                }
                $names | ForEach-Object { $_ }
                $global:LASTEXITCODE = 0
                return
            }

            if ($mode -eq 'word') {
                Get-EntryCompletion -map $completeMap -language conf -wordToComplete $(if ($null -eq $Word) { '' } else { $Word })
                $global:LASTEXITCODE = 0
                return
            }

            $global:LASTEXITCODE = 2
            return
        }

        $map = Import-ConfigMap -Map $map | Assert-ConfigMap

        if ($verb -eq 'list') {
            $listEntry = if ($confEntry) {
                $confEntry
            }
            else {
                @($RemainingArguments | Where-Object { $_ } | Select-Object -First 1)
            }

            if (-not $listEntry -or @($listEntry).Count -eq 0) {
                Write-MapHelp -map $map -invocation $MyInvocation -language "conf"
                return
            }

            $entryName = [string]@($listEntry)[0]
            $operationContext = New-ConfigMapOperationContext
            $subEntry = Get-MapEntry $map $entryName -language "conf" -OperationContext $operationContext
            if (-not $subEntry) {
                throw "Entry '$entryName' not found. Run 'qconf list' to see all available entries."
            }

            Invoke-WithEntrySettings -Map $map -EntryKey $entryName -Entry $subEntry -OperationContext $operationContext -ScriptBlock {
                $options = Get-CompletionList $subEntry -listKey "options" -language "conf" -maxDepth 1
                $current = Invoke-Get $subEntry -bound @{ options = $options }
                $result = ConvertTo-MapResult $current $entryName $subEntry $options
                Write-Host "$($result.Path)  Active: $(@($result.Active) -join ', ')  Value: $($result.Value)  Options: $(@($result.Options) -join ', ')"
            }
            return
        }

        if (-not $verb) {
            Write-MapHelp -map $map -invocation $MyInvocation -language "conf"
            return
        }

        Write-Verbose "entry=$confEntry command=$verb"
        $operationContext = New-ConfigMapOperationContext

        switch ($verb) {
            "set" {
                if (-not $confEntry) {
                    throw "The set command requires an entry."
                }
                $subEntry = Get-MapEntry $map $confEntry -language "conf" -OperationContext $operationContext
                if (!$subEntry) {
                    throw "Entry '$confEntry' not found. Run 'qconf list' to see all available entries."
                }

                $optionKey = $value
                $options = Get-CompletionList $subEntry -listKey "options" -language "conf" -maxDepth 1
                if ([string]::IsNullOrWhiteSpace($optionKey) -or -not $options.Contains($optionKey)) {
                    throw "Unknown option '$optionKey' for entry '$confEntry'. Available options: $($options.Keys -join ', ')."
                }
                $optionValue = $options[$optionKey]

                $bound = @{}
                foreach ($boundKey in $PSBoundParameters.Keys) {
                    $bound[$boundKey] = $PSBoundParameters[$boundKey]
                }
                $bound.key = $optionKey
                $bound.value = $optionValue
                Invoke-WithEntrySettings -Map $map -EntryKey "$confEntry" -Entry $subEntry -OperationContext $operationContext -ScriptBlock {
                    Invoke-Set $subEntry -bound $bound
                }
            }
            "get" {
                $entries = $confEntry
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
                throw "command '$verb' not supported"
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
