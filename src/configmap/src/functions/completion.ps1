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
        $maxDepth = -1
    )

    if ($maxDepth -eq 0) {
        return @{}
    }

    if (!$groupMarker) {
        $groupMarker = $flatten ? "*" : ""
    }

    $reservedKeys = $language ? (Get-MapLanguage $language).reservedKeys : @()

    $list = $map.$listKey ? $map.$listKey : $map
    $list = $list -is [scriptblock] ? (Invoke-Command -ScriptBlock $list) : $list

    # switch automatically iterates over the array, so we need to wrap it in a single element array
    $r = switch (@(,$list)) {
        { $_ -is [System.Collections.IDictionary] } {
            $result = [ordered]@{}

            foreach ($kvp in $list.GetEnumerator()) {
                # Handle #include directives first (before reserved keys check)
                if ($kvp.key -eq "#include") {
                    $includedEntries = Merge-IncludeDirectives $kvp.value -baseDir $map._baseDir -flatten:$flatten -leafsOnly:$leafsOnly -separator $separator -language $language
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
                $subEntries = Get-MapEntryList $entry -listKey $listKey -flatten:$flatten -leafsOnly:$leafsOnly -separator $separator -language $language -maxDepth ($maxDepth - 1)

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
        $maxDepth = -1
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
        $language = $null
    )

    $result = [ordered]@{}

    if (!$baseDir) { $baseDir = $PWD.Path }

    foreach ($kvp in $includes.GetEnumerator()) {
        $dirName = $kvp.Key
        $includeConfig = $kvp.Value

        $includedMap = Import-IncludedConfigMap -DirectoryName $dirName -BaseDir $baseDir -Cache @{} -Loading @{}
        if (!$includedMap) {
            continue
        }

        # Process the included map
        $includedEntries = Get-MapEntryList $includedMap -flatten:$flatten -leafsOnly:$leafsOnly -separator $separator -language $language

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

function Get-CompletionIncludedMap {
    param(
        [string]$DirectoryName,
        [string]$BaseDir,
        [hashtable]$Cache,
        [hashtable]$Loading
    )

    return Import-IncludedConfigMap -DirectoryName $DirectoryName -BaseDir $BaseDir -Cache $Cache -Loading $Loading
}

function Add-EntryCompletionCandidates {
    param(
        [System.Collections.IDictionary]$Map,
        [string]$TreePrefix,
        [string]$FlatPrefix,
        [string]$Separator,
        [string]$Language,
        [System.Collections.Generic.HashSet[string]]$Candidates,
        [hashtable]$IncludeCache,
        [hashtable]$LoadingIncludes
    )

    $reservedKeys = $Language ? (Get-MapLanguage $Language).reservedKeys : @()
    $list = $Map.list ? $Map.list : $Map
    $list = $list -is [scriptblock] ? (Invoke-Command -ScriptBlock $list) : $list

    if ($list -is [array]) {
        foreach ($item in $list) {
            $Candidates.Add("$TreePrefix$item") | Out-Null
            $Candidates.Add("$FlatPrefix$item") | Out-Null
        }
        return
    }

    if ($list -isnot [System.Collections.IDictionary]) {
        throw "$($list.GetType().FullName) type not supported"
    }

    foreach ($kvp in $list.GetEnumerator()) {
        if ($kvp.Key -eq '#include') {
            if ($kvp.Value -isnot [System.Collections.IDictionary]) {
                continue
            }

            foreach ($include in $kvp.Value.GetEnumerator()) {
                $includedMap = Get-CompletionIncludedMap -DirectoryName "$($include.Key)" -BaseDir $Map._baseDir -Cache $IncludeCache -Loading $LoadingIncludes
                if (!$includedMap) {
                    continue
                }

                $usePrefix = $include.Value -is [System.Collections.IDictionary] -and $include.Value.prefix -eq $true
                $includedTreePrefix = if ($usePrefix) { "$TreePrefix$($include.Key)$Separator" } else { $TreePrefix }
                $includedFlatPrefix = if ($usePrefix) { "$FlatPrefix$($include.Key)$Separator" } else { $FlatPrefix }

                Add-EntryCompletionCandidates -Map $includedMap -TreePrefix $includedTreePrefix -FlatPrefix $includedFlatPrefix -Separator $Separator -Language $Language -Candidates $Candidates -IncludeCache $IncludeCache -LoadingIncludes $LoadingIncludes
            }

            continue
        }

        if ($kvp.Key -in $reservedKeys -or $kvp.Key -eq 'list') {
            continue
        }

        $entry = $kvp.Value
        $treeKey = "$TreePrefix$($kvp.Key)"
        $flatKey = "$FlatPrefix$($kvp.Key)"

        if (!(Test-IsParentEntry $entry -ReservedKeys $reservedKeys)) {
            $Candidates.Add($treeKey) | Out-Null
            $Candidates.Add($flatKey) | Out-Null
            continue
        }

        $Candidates.Add($treeKey) | Out-Null
        $Candidates.Add("$flatKey*") | Out-Null

        Add-EntryCompletionCandidates -Map $entry -TreePrefix "$treeKey$Separator" -FlatPrefix $FlatPrefix -Separator $Separator -Language $Language -Candidates $Candidates -IncludeCache $IncludeCache -LoadingIncludes $LoadingIncludes

        if ($Language -eq 'build' -and $entry -is [System.Collections.IDictionary] -and -not $entry.Contains('all')) {
            $invokableChildren = Get-BuildAllChildren $entry -Language $Language -ParentKey $kvp.Key -Separator $Separator
            if ($invokableChildren.Count -gt 0) {
                $Candidates.Add("$treeKey$Separator" + 'all') | Out-Null
                $Candidates.Add("$flatKey.all") | Out-Null
            }
        }
    }
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
    Add-EntryCompletionCandidates -Map $map -TreePrefix '' -FlatPrefix '' -Separator '.' -Language $language -Candidates $allKeys -IncludeCache @{} -LoadingIncludes @{}

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
