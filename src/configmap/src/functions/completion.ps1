function Get-MapEntryList {
    <#
    .SYNOPSIS
        Walks a configuration map and returns its entries in flattened or hierarchical form
    .PARAMETER map
        The configuration map to process. Can be a dictionary, array, scriptblock or string
    .PARAMETER flatten
        If true, flattens hierarchical commands into a single level. If false, maintains hierarchy with separators
    .PARAMETER separator
        The separator to use between parent and child command names when not flattened
    .PARAMETER groupMarker
        The marker to append to parent command names when flattened
    .PARAMETER listKey
        The key used to identify nested command lists
    .PARAMETER language
        The language to use for determining reserved keys (e.g., "build", "conf")
    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] containing the processed command list
    #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [ValidateScript({
                # the function do not suppurt strings, but ValidateScript iterates over the array, so for string[] we'll get string items here.
                # see: https://github.com/PowerShell/PowerShell/issues/6185
                $_ -is [System.Collections.IDictionary] -or $_ -is [array] -or $_ -is [scriptblock] -or $_ -is [string]
            })]
        $map,
        [switch][bool]$flatten = $false,
        [switch][bool]$leafsOnly = $false,
        $separator = ".",
        $groupMarker = $null,
        $listKey = "list",
        $language = $null,
        $maxDepth = -1,
        [hashtable]$OperationContext = $null
    )

    if ($maxDepth -eq 0) {
        return @{}
    }

    if (!$groupMarker) {
        $groupMarker = $flatten ? "*" : ""
    }

    $reservedKeys = $language ? (Get-MapLanguage $language).reservedKeys : @()
    if ($null -eq $OperationContext) {
        $OperationContext = New-ConfigMapOperationContext
    }

    $list = $map.$listKey ? $map.$listKey : $map
    $list = $list -is [scriptblock] ? (Invoke-Command -ScriptBlock $list) : $list

    # switch automatically iterates over the array, so we need to wrap it in a single element array
    $r = switch (@(,$list)) {
        { $_ -is [System.Collections.IDictionary] } {
            $result = [ordered]@{}

            foreach ($kvp in $list.GetEnumerator()) {
                # Handle #include directives first (before reserved keys check)
                if ($kvp.key -eq "#include") {
                    $includedEntries = Merge-IncludeDirectives $kvp.value `
                        -baseDir $map._baseDir `
                        -flatten:$flatten `
                        -leafsOnly:$leafsOnly `
                        -separator $separator `
                        -language $language `
                        -OperationContext $OperationContext
                    foreach ($inc in $includedEntries.GetEnumerator()) {
                        $result[$inc.Key] = $inc.Value
                    }
                    continue
                }

                if ($kvp.key -in $reservedKeys -or $kvp.key -eq $listKey) {
                    continue
                }

                $entry = $kvp.value

                if (!(Test-IsParentEntry $entry -reservedKeys $reservedKeys)) {
                    $result["$($kvp.key)"] = $entry
                    continue
                }

                # Add parent marker
                if (!$leafsOnly) {
                    $result["$($kvp.key)$groupMarker"] = $entry
                }

                # Get nested entries and add them with appropriate prefixes
                $subEntries = Get-MapEntryList $entry `
                    -listKey $listKey `
                    -flatten:$flatten `
                    -leafsOnly:$leafsOnly `
                    -separator $separator `
                    -language $language `
                    -maxDepth ($maxDepth - 1) `
                    -OperationContext $OperationContext

                foreach ($sub in $subEntries.GetEnumerator()) {
                    $subKey = $flatten ? $sub.Key : "$($kvp.key)$separator$($sub.Key)"
                    $result[$subKey] = $sub.value
                }

                if ($language -eq 'build' -and $entry -is [System.Collections.IDictionary] -and -not $entry.Contains('all')) {
                    $invokableChildren = Get-BuildAllChildren $entry -Language $language -ParentKey $kvp.key -Separator $separator
                    if ($invokableChildren.Count -gt 0) {
                        $allKey = if ($flatten) { "$($kvp.key).all" } else { "$($kvp.key)${separator}all" }
                        $result[$allKey] = New-BuildAllEntry
                    }
                }
            }

            return $result
        }
        { $_ -is [array] } {
            $result = [ordered]@{}
            $subEntries = $list | ForEach-Object {
                $r = [ordered]@{}
            } {
                $r[$_] = $_
            } {
                $r
            }

            if ($subEntries) {
                foreach ($sub in $subEntries.GetEnumerator()) {
                    if ($sub.key -in $reservedKeys -or $sub.key -eq $listKey) {
                        continue
                    }
                    $result[$sub.key] = $sub.value
                }
            }
            return $result
        }
        { $_ -is [string] } {
            throw "string type not supported"
        }
        default {
            throw "$($_.GetType().FullName) type not supported"
        }
    }

    return $r
}

function Get-CompletionList {
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        $map,
        [switch][bool]$flatten = $false,
        [switch][bool]$leafsOnly = $false,
        $separator = ".",
        $groupMarker = $null,
        $listKey = "list",
        $language = $null,
        $maxDepth = -1,
        [hashtable]$OperationContext = $null
    )

    return Get-MapEntryList @PSBoundParameters
}

function Merge-IncludeDirectives {
    <#
    .SYNOPSIS
        Processes #include directives and merges included map entries
    .PARAMETER includes
        Hashtable with include configuration (directory names as keys with prefix option)
    .PARAMETER baseDir
        Base directory for resolving include paths. Defaults to $PWD if not specified.
    #>
    param(
        [System.Collections.IDictionary]$includes,
        [string]$baseDir = $null,
        [switch][bool]$flatten = $false,
        [switch][bool]$leafsOnly = $false,
        $separator = ".",
        $language = $null,
        [hashtable]$OperationContext = $null
    )

    $result = [ordered]@{}

    if (!$baseDir) { $baseDir = $PWD.Path }
    if ($null -eq $OperationContext) {
        $OperationContext = New-ConfigMapOperationContext
    }

    foreach ($kvp in $includes.GetEnumerator()) {
        $dirName = $kvp.Key
        $includeConfig = $kvp.Value

        $includePath = Join-Path $baseDir $dirName
        $mapFile = Join-Path $includePath '.build.map.ps1'
        $fullMapPath = [System.IO.Path]::GetFullPath($mapFile)

        if (Test-Path -LiteralPath $mapFile -PathType Leaf) {
            $OperationContext.Dependencies[$fullMapPath] = (Get-Item -LiteralPath $mapFile).LastWriteTimeUtc.Ticks
        }
        else {
            $OperationContext.Dependencies[$fullMapPath] = $null
        }

        $includedMap = Import-IncludedConfigMap `
            -DirectoryName $dirName `
            -BaseDir $baseDir `
            -Cache $OperationContext.IncludeCache `
            -Loading $OperationContext.LoadingIncludes
        if (!$includedMap) {
            continue
        }

        # Process the included map
        $includedEntries = Get-MapEntryList $includedMap `
            -flatten:$flatten `
            -leafsOnly:$leafsOnly `
            -separator $separator `
            -language $language `
            -OperationContext $OperationContext

        # Apply prefix if configured
        $usePrefix = $false
        if ($includeConfig -is [System.Collections.IDictionary]) {
            $usePrefix = $includeConfig.prefix -eq $true
        }

        foreach ($entry in $includedEntries.GetEnumerator()) {
            if ($usePrefix) {
                $key = "$dirName$separator$($entry.Key)"
            }
            else {
                $key = $entry.Key
            }

            $result[$key] = $entry.Value
        }
    }

    return $result
}

function Get-EntryCompletion(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary]
        })]
    $map,
    [ValidateSet("build", "conf")]
    $language,
    $commandName,
    $parameterName,
    $wordToComplete,
    $commandAst,
    $fakeBoundParameters
) {
    $allKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $cache = Get-ConfigMapDiscoveryCache -Map $map -Language $language
    if ($cache) {
        foreach ($entryList in @($cache.entries.hierarchical, $cache.entries.flatten)) {
            foreach ($entry in @($entryList)) {
                if ($null -ne $entry -and $entry.key) {
                    $allKeys.Add([string]$entry.key) | Out-Null
                }
            }
        }
    }
    else {
        foreach ($entryList in @(
                (Get-MapEntryList -map $map -language $language),
                (Get-MapEntryList -map $map -flatten -language $language)
            )) {
            foreach ($key in $entryList.Keys) {
                $allKeys.Add($key) | Out-Null
            }
        }
    }

    return $allKeys | Sort-Object | ? { $_.startswith($wordToComplete) }
}

function Get-EntryDynamicParam(
    [System.Collections.IDictionary] $map,
    $key,
    $command,
    [int]$skip = 0,
    $bound
) {
    if (!$key) { return @() }

    $selectedEntry = Get-MapEntry $map $key
    if (!$selectedEntry) { return @() }
    if (Test-BuildAllEntry $selectedEntry) { return @() }

    # Use the command parameter to determine which command to extract, defaulting to "exec"
    $commandKey = $command ? $command : "exec"
    $entryCommand = Get-EntryCommand $selectedEntry $commandKey
    if (!$entryCommand) { return @() }
    $entryContext = if ($selectedEntry -is [System.Collections.IDictionary]) { $selectedEntry } else { $null }
    $p = Get-ScriptArgs $entryCommand -skip $skip -entry $entryContext

    return $p
}

function Get-ScriptArgs {
    [OutputType([System.Management.Automation.RuntimeDefinedParameterDictionary])]
    param(
        [scriptblock]$func,
        [int]$skip = 0,
        $exclude = @("$_context", "$_self"),
        [System.Collections.IDictionary]$entry = $null
    )
    function Get-SingleArg {
        [OutputType([System.Management.Automation.RuntimeDefinedParameter])]
        param(
            [System.Management.Automation.Language.ParameterAst] $ast,
            [System.Collections.IDictionary] $entryContext = $null
        )

        $paramAttributesCollect = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
        
        $paramAttribute = New-Object -Type System.Management.Automation.ParameterAttribute
        $paramAttributesCollect.Add($paramAttribute)
    
        $paramType = $ast.StaticType
    
        foreach ($attr in $ast.Attributes) {
            if ($attr -is [System.Management.Automation.Language.TypeConstraintAst]) {
                if ($attr.TypeName.ToString() -eq "switch") {
                    $paramType = [switch]
                }
                else {
                    # $newAttr = New-Object -type System.Management.Automation.PSTypeNameAttribute($attr.TypeName.Name)
                    # $paramAttributesCollect.Add($newAttr)
                }
            }
            elseif ($attr -is [System.Management.Automation.Language.AttributeAst]) {
                $typeName = $attr.TypeName.ToString() -replace '^.*\.', ''
                if ($typeName -eq "ValidateSet") {
                    $values = @()
                    foreach ($arg in $attr.PositionalArguments) {
                        if ($arg -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                            $values += $arg.Value
                        }
                    }
                    if ($values.Count -gt 0) {
                        # Resolve @__siblingKey reference to entry's sibling array
                        if ($values.Count -eq 1 -and $values[0] -match '^@(.+)$') {
                            if ($entryContext -isnot [System.Collections.IDictionary]) {
                                throw "entryContext is not a dictionary"
                            }
                            $refKey = $Matches[1]
                            $resolved = $entryContext[$refKey]
                            if ($resolved) {
                                if ($resolved -is [array]) {
                                    $values = @($resolved | ForEach-Object { [string]$_ })
                                }
                                elseif ($resolved -is [scriptblock]) {
                                    $fromSb = & $resolved
                                    if ($null -ne $fromSb) {
                                        $values = @(@($fromSb) | ForEach-Object { [string]$_ })
                                    }
                                } else {
                                    throw "resolved value is not an array or scriptblock"
                                }
                            }
                        }
                        if ($values.Count -gt 0) {
                            $validateSetAttr = New-Object System.Management.Automation.ValidateSetAttribute([string[]]$values)
                            $paramAttributesCollect.Add($validateSetAttr)
                        }
                    }
                }
            }
        }
        
        # Create parameter with name, type, and attributes
        $name = $ast.Name.ToString().Trim("`$")
        $dynParam = New-Object -Type System.Management.Automation.RuntimeDefinedParameter($name, $paramType, $paramAttributesCollect)
    
        return $dynParam
    }

    
    # Add parameter to parameter dictionary and return the object
    $paramDictionary = New-Object `
        -Type System.Management.Automation.RuntimeDefinedParameterDictionary
    
    # Check if ParamBlock exists before accessing Parameters
    if ($func.AST.ParamBlock -and $func.AST.ParamBlock.Parameters) {
        $parameters = $func.AST.ParamBlock.Parameters
        
        $skipped = 0
        foreach ($param in $parameters) {
            if ("$($param.Name)" -in $exclude) {
                continue
            }
            if ($skipped -lt $skip) {
                $skipped++
                continue
            }
            $dynParam = Get-SingleArg $param $entry
            $paramDictionary.Add($dynParam.Name, $dynParam)
        }
    }
    
    return $paramDictionary
}
