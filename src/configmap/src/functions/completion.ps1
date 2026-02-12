function Get-CompletionList {
    <#
    .SYNOPSIS
        Gets a flattened or hierarchical list of commands from a configuration map
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

    $r = switch ($true) {
        { $list -is [System.Collections.IDictionary] } {
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
                $entryInfo = Test-IsParentEntry $entry $listKey -reservedKeys $reservedKeys

                if (!$entryInfo.IsParent) {
                    $result["$($kvp.key)"] = $entry
                    continue
                }

                # Add parent marker
                if (!$leafsOnly) {
                    $result["$($kvp.key)$groupMarker"] = $entry
                }

                # Get nested entries and add them with appropriate prefixes
                $subEntries = Get-CompletionList $entry -listKey $listKey -flatten:$flatten -leafsOnly:$leafsOnly -separator $separator -language $language -maxDepth ($maxDepth - 1)

                foreach ($sub in $subEntries.GetEnumerator()) {
                    $subKey = $flatten ? $sub.Key : "$($kvp.key)$separator$($sub.Key)"
                    $result[$subKey] = $sub.value
                }
            }

            return $result
        }
        { $list -is [array] } {
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
        { $list -is [string] } {
            throw "string type not supported"
        }
        default {
            throw "$($list.GetType().FullName) type not supported"
        }
    }

    return $r
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

        # Resolve the include directory path
        $includePath = Join-Path $baseDir $dirName
        if (!(Test-Path $includePath -PathType Container)) {
            Write-Warning "Include directory not found: $includePath"
            continue
        }

        # Look for map file in the included directory
        $mapFile = Join-Path $includePath ".build.map.ps1"
        if (!(Test-Path $mapFile)) {
            Write-Warning "Map file not found in include directory: $mapFile"
            continue
        }

        # Load the map from the included directory
        $includedMap = . $mapFile
        
        $includedMap = Add-BaseDir $includedMap $includePath

        # Process the included map
        $includedEntries = Get-CompletionList $includedMap -flatten:$flatten -leafsOnly:$leafsOnly -separator $separator -language $language

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
    # For hierarchical completion, we need both flattened and tree structures
    $flatList = Get-CompletionList $map -flatten:$true -language $language
    $treeList = Get-CompletionList $map -flatten:$false -language $language

    # Combine both lists and remove duplicates
    $allKeys = @($flatList.Keys) + @($treeList.Keys) | Sort-Object -Unique

    return $allKeys | ? { $_.startswith($wordToComplete) }
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

    # Use the command parameter to determine which command to extract, defaulting to "exec"
    $commandKey = $command ? $command : "exec"
    $entryCommand = Get-EntryCommand $selectedEntry $commandKey
    if (!$entryCommand) { return @() }
    $p = Get-ScriptArgs $entryCommand -skip $skip

    return $p
}

function Get-ScriptArgs {
    [OutputType([System.Management.Automation.RuntimeDefinedParameterDictionary])]
    param(
        [scriptblock]$func,
        [int]$skip = 0,
        $exclude = @("$_context", "$_self")
    )
    function Get-SingleArg {
        [OutputType([System.Management.Automation.RuntimeDefinedParameter])]
        param([System.Management.Automation.Language.ParameterAst] $ast)
    
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
            $dynParam = Get-SingleArg $param
            $paramDictionary.Add($dynParam.Name, $dynParam)
        }
    }
    
    return $paramDictionary
}

