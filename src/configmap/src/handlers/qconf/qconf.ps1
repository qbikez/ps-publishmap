. "$PSScriptRoot\entry-types.ps1"
. "$PSScriptRoot\..\..\.config-utils.ps1"

$script:languages.conf = @{
    reservedKeys = @("exec", "list", "options", "#include", "_baseDir", "_sourceFile", "_settings", "_dependsOn", "_internal", "_template", "description", "validate", "get", "set")
}

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
                    $entryName = if ($fakeBoundParameters.entry) {
                        [string]$fakeBoundParameters.entry
                    }
                    elseif ($fakeBoundParameters.command -notin @('set', 'get', 'show', 'list', 'help', 'init', '!init', '!complete')) {
                        [string]$fakeBoundParameters.command
                    }
                    $entryValue = Get-MapEntry $map $entryName -language conf
                    if (!$entryValue) {
                        throw "entry '$entryName' not found"
                    }
                    $options = Get-CompletionList $entryValue -listKey "options" -language "conf" -maxDepth 1
                    return $options.Keys | ? { $_.startswith($wordToComplete) }
                }
                catch {
                    return "ERROR [-value]: $($_.Exception.Message) $($_.ScriptStackTrace)"
                }
            })]
        [string]$value = $null,

        [Parameter(Position = 1, DontShow)]
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete)
                @('get', 'set', 'show') | Where-Object { $_.StartsWith($wordToComplete, [StringComparison]::OrdinalIgnoreCase) }
            })]
        [string]$action,

        [Parameter(Position = 2, DontShow)]
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    if ($fakeBoundParameters.action -ne 'set') { return @() }
                    $verbs = @('set', 'get', 'show', 'list', 'help', 'init', '!init', '!complete')
                    $entryName = if ($fakeBoundParameters.entry) {
                        [string]$fakeBoundParameters.entry
                    }
                    elseif ($fakeBoundParameters.command -notin $verbs) {
                        [string]$fakeBoundParameters.command
                    }
                    if (-not $entryName) { return @() }

                    $map = Import-ConfigMap -Map $fakeBoundParameters.map -Fallback ".configuration.map.ps1" | Assert-ConfigMap
                    $entryValue = Get-MapEntry $map $entryName -language conf
                    if (-not $entryValue) { return @() }
                    $options = Get-CompletionList $entryValue -listKey "options" -language "conf" -maxDepth 1
                    return @($options.Keys | Where-Object { "$_".StartsWith($wordToComplete, [StringComparison]::OrdinalIgnoreCase) })
                }
                catch {
                    return @()
                }
            })]
        [string]$option,

        [Parameter(DontShow)]
        [string]$Word,
        [Parameter(DontShow)]
        [switch]$Params,

        # Script/tool-readable MapResult object instead of host-formatted status.
        [switch]$porcelain,

        $map = "./.configuration.map.ps1",

        [Parameter(ValueFromRemainingArguments = $true, DontShow = $true)]
        [string[]]$RemainingArguments
    )

    dynamicparam {
        try {
            $verbs = @('set', 'get', 'show', 'list', 'help', 'init', '!init', '!complete')
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

            # RemainingArguments carry process-owned verbs when qbuild forwards
            # (e.g. RemainingArguments = set,dev). Detect set before verb parsing.
            $remainingHead = @(
                $RemainingArguments | Where-Object { $null -ne $_ -and "$_" -ne '' } | Select-Object -First 1
            )
            $impliesSet = $command -eq 'set' -or $action -eq 'set' -or
                $PSBoundParameters.ContainsKey('value') -or
                ($remainingHead.Count -gt 0 -and $remainingHead[0] -eq 'set')

            $dynamicOperation = if ($impliesSet) { 'set' } else { 'get' }
            $skip = if ($dynamicOperation -eq 'set') { 3 } else { 0 }

            $result = Get-EntryDynamicParam $map "$dynamicEntry.$dynamicOperation" -skip $skip -bound $PSBoundParameters
            if (-not $result) {
                $result = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
            }

            # Always expose set custom params so qbuild can forward opaque names
            # discovered via !complete -params even when the verb arrives later.
            if ($dynamicOperation -ne 'set') {
                $setExtras = Get-EntryDynamicParam $map "$dynamicEntry.set" -skip 3 -bound $PSBoundParameters
                if ($setExtras) {
                    foreach ($name in @($setExtras.Keys)) {
                        if (-not $result.ContainsKey($name)) {
                            $result.Add($name, $setExtras[$name])
                        }
                    }
                }
            }

            return $result
        }
        catch {
            return "ERROR [dynamic]: $($_.Exception.Message) $($_.ScriptStackTrace)"
        }
    }

    process {
        $verbs = @('set', 'get', 'show', 'list', 'help', 'init', '!init', '!complete')
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

        if ($verb -in @('get', 'set', 'show', 'list') -and -not $confEntry -and $action) {
            $confEntry = $action
            if ($verb -eq 'set' -and -not $PSBoundParameters.ContainsKey('value') -and $option) {
                $value = $option
            }
        }
        elseif (-not $verb -and $confEntry -and $action -in @('get', 'set', 'show')) {
            $verb = $action
            if ($verb -eq 'set' -and -not $PSBoundParameters.ContainsKey('value') -and $option) {
                $value = $option
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
                'show' {
                    $verb = 'show'
                    $operationArgs = @($operationArgs | Select-Object -Skip 1)
                }
            }
        }

        if (-not $verb -and $confEntry) {
            $verb = if ($PSBoundParameters.ContainsKey('value')) { 'set' } else { 'get' }
        }

        # Skip noise during tab-completion protocol calls.
        if ($verb -ne '!complete') {
            Write-ConfigMapDeprecatedProcessCliWarning -CliName 'qconf' -ProcessType 'options'
        }

        if ($verb -eq "help") {
            Write-Host "QCONF (deprecated)"
            Write-Host "Prefer qbuild with _settings.process = 'options' in .build.map.ps1"
            Write-Host "A command line tool to manage configuration maps"
            Write-Host ""
            Write-Host "Usage:"
            Write-Host "qconf <entry> get"
            Write-Host "qconf <entry> get -porcelain"
            Write-Host "qconf <entry> set <option>"
            Write-Host "qconf <entry> show"
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
                $names.Add('porcelain') | Out-Null
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
                $prefix = if ($null -eq $Word) { '' } else { [string]$Word }
                if ($completeEntry) {
                    if ($tokens.Count -eq 0) {
                        @('get', 'set', 'show') |
                            Where-Object { $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }
                    }
                    elseif ($tokens[0] -eq 'set') {
                        $entryValue = Get-MapEntry $completeMap $completeEntry -language conf
                        if ($entryValue) {
                            $options = Get-CompletionList $entryValue -listKey 'options' -language conf -maxDepth 1
                            $options.Keys |
                                Where-Object { "$_".StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }
                        }
                    }
                }
                else {
                    Get-EntryCompletion -map $completeMap -language conf -wordToComplete $prefix
                }
                $global:LASTEXITCODE = 0
                return
            }

            $global:LASTEXITCODE = 2
            return
        }

        $map = Import-ConfigMap -Map $map | Assert-ConfigMap

        if ($verb -in @('list', 'show')) {
            $listEntry = if ($confEntry) {
                $confEntry
            }
            else {
                @($RemainingArguments | Where-Object { $_ } | Select-Object -First 1)
            }

            if (-not $listEntry -or @($listEntry).Count -eq 0) {
                if ($verb -eq 'show') {
                    throw "The show command requires an entry. Example: qconf <entry> show"
                }
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
                Add-ConfigEntryTypeCommands -Entry $subEntry
                $options = Get-CompletionList $subEntry -listKey "options" -language "conf" -maxDepth 1
                $current = Invoke-Get $subEntry -bound @{ options = $options }
                $result = ConvertTo-MapResult $current $entryName $subEntry $options
                Write-QConfStatus `
                    -EntryName $entryName `
                    -Result $result `
                    -Description $subEntry.description `
                    -HasValidation ([bool]$subEntry.validate)
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
                $hasOptions = $options -and @($options.Keys).Count -gt 0

                if ($hasOptions) {
                    if ([string]::IsNullOrWhiteSpace($optionKey) -or -not $options.Contains($optionKey)) {
                        throw "Unknown option '$optionKey' for entry '$confEntry'. Available options: $($options.Keys -join ', ')."
                    }
                    $optionValue = $options[$optionKey]
                }
                else {
                    # Option-less entries rely on opaque/custom set parameters.
                    $optionValue = $null
                }

                $bound = @{}
                foreach ($boundKey in $PSBoundParameters.Keys) {
                    $bound[$boundKey] = $PSBoundParameters[$boundKey]
                }
                $bound.key = $optionKey
                $bound.value = $optionValue
                $setExtras = @($operationArgs | Where-Object { $null -ne $_ -and "$_" -ne '' })
                Invoke-WithEntrySettings -Map $map -EntryKey "$confEntry" -Entry $subEntry -OperationContext $operationContext -ScriptBlock {
                    Add-ConfigEntryTypeCommands -Entry $subEntry
                    Invoke-Set $subEntry -bound $bound -extra $setExtras
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
                            Add-ConfigEntryTypeCommands -Entry $subEntry

                            $value = Invoke-Get $subEntry -bound $bound

                            $result = ConvertTo-MapResult $value $entryName $subEntry $options
                            if ($porcelain) {
                                $result | Write-Output
                            }
                            else {
                                Write-QConfStatus `
                                    -EntryName $entryName `
                                    -Result $result `
                                    -Description $subEntry.description `
                                    -HasValidation ([bool]$subEntry.validate)
                            }
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

function Write-QConfStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntryName,
        [Parameter(Mandatory = $true)]
        $Result,
        [string]$Description,
        [bool]$HasValidation
    )

    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host $EntryName -NoNewline -ForegroundColor Green
    if ($Description) {
        Write-Host "  $Description" -ForegroundColor White
    }
    else {
        Write-Host ""
    }

    $active = @($Result.Active) -join ', '
    if (-not $active) { $active = '<none>' }

    $value = if ($Result.Value -is [System.Collections.IDictionary] -or $Result.Value -is [array]) {
        $Result.Value | ConvertTo-Json -Compress -Depth 4
    }
    elseif ($null -eq $Result.Value) {
        '<none>'
    }
    else {
        [string]$Result.Value
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $rows.Add([pscustomobject]@{
            Label = 'Active'
            Value = $active
            Glyph = if ($active -eq '<none>') { [char]0x25CB } else { [char]0x25CF }
            Color = if ($active -eq '<none>') { 'Yellow' } else { 'Green' }
        })
    $rows.Add([pscustomobject]@{
            Label = 'Value'
            Value = $value
            Glyph = ' '
            Color = 'White'
        })
    $rows.Add([pscustomobject]@{
            Label = 'Options'
            Value = @($Result.Options) -join ', '
            Glyph = ' '
            Color = 'White'
        })

    if ($HasValidation) {
        $rows.Add([pscustomobject]@{
                Label = 'Valid'
                Value = if ($Result.IsValid -eq $true) { 'yes' } elseif ($Result.IsValid -eq $false) { 'no' } else { 'unknown' }
                Glyph = if ($Result.IsValid -eq $true) { [char]0x2713 } elseif ($Result.IsValid -eq $false) { [char]0x2717 } else { [char]0x25CB }
                Color = if ($Result.IsValid -eq $true) { 'Green' } elseif ($Result.IsValid -eq $false) { 'Red' } else { 'Yellow' }
            })
    }

    for ($index = 0; $index -lt $rows.Count; $index++) {
        $row = $rows[$index]
        $branch = if ($index -eq $rows.Count - 1) { [char]0x2514 } else { [char]0x251C }
        Write-Host "    $branch─ " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($row.Glyph) " -NoNewline -ForegroundColor $row.Color
        Write-Host ("{0,-8}" -f $row.Label) -NoNewline -ForegroundColor DarkGray
        Write-Host $row.Value -ForegroundColor $row.Color
    }
    Write-Host ""
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

# Canonical process type for qbuild maps; CLI alias remains qconf.
Register-ConfigMapCliProcess -Name 'options' -CliName 'qconf'
