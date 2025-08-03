#requires -version 7.0

$languages = @{
    "build" = @{
        reservedKeys = @("exec", "list")
    }
    "conf"  = @{
        reservedKeys = @("options", "exec", "list", "get", "set", "validate")
    }
}

function Get-MapLanguage {
    param([ValidateSet("build", "conf")]$language)
    return $languages.$language
}

# in order to make imports from the map file work globally, we have to call dot-source from top-level scope. 
# hence this pattern: 
# $map = Resolve-ConfigMap $map | % { . $_ } | Validate-ConfigMap
function Resolve-ConfigMap {
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]
        # somehow validateScript is throwing an error when $map is null
        # [ValidateScript({ $null -eq $_ -or $_ -is [string] -or $_ -is [System.Collections.IDictionary] })]
        $map,
        [Parameter(Mandatory = $false)]
        $fallback
    )
    
    # Set default map file if null
    if (!$map) {
        if (!$fallback) {
            throw "map is null and defaultMapFile is not provided"
            return $null
        }
        $map = $fallback 
    }
    
    # Load map from file if it's a string path
    if ($map -is [string]) {
        if (!(Test-Path $map)) {
            throw "map file '$map' not found"
            return $null
        }
        return $map
    }
    
    return $map
}

function Validate-ConfigMap {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $map
    )
    # Validate that we have a loaded map
    if (!$map) {
        throw "failed to load map"
        return $null
    }

    if ($map -isnot [System.Collections.IDictionary]) {
        throw "map is not a dictionary"
    }
    
    return $map
}


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
    .PARAMETER reservedKeys
        Array of reserved keys that should be skipped during processing
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
        $reservedKeys = $null
    )
    
    if (!$groupMarker) {
        $groupMarker = $flatten ? "*" : ""
    }

    $list = $map.$listKey ? $map.$listKey : $map
    $list = $list -is [scriptblock] ? (Invoke-Command -ScriptBlock $list) : $list
        
    $r = switch ($true) {
        { $list -is [System.Collections.IDictionary] } {
            $result = [ordered]@{}
    
            foreach ($kvp in $list.GetEnumerator()) {
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
                $subEntries = Get-CompletionList $entry -listKey $listKey -flatten:$flatten -leafsOnly:$leafsOnly -reservedKeys $reservedKeys
                
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
    $flatList = Get-CompletionList $map -flatten:$true -reservedKeys $languages.$language.reservedKeys
    $treeList = Get-CompletionList $map -flatten:$false -reservedKeys $languages.$language.reservedKeys
    
    # Combine both lists and remove duplicates
    $allKeys = @($flatList.Keys) + @($treeList.Keys) | Sort-Object -Unique
    
    return $allKeys | ? { $_.startswith($wordToComplete) }
}

function Get-EntryDynamicParam(
    [System.Collections.IDictionary] $map, 
    $key, 
    $command, 
    $bound
) {
    if (!$key) { return @() }

    $selectedEntry = Get-MapEntry $map $key
    if (!$selectedEntry) { return @() }
    
    # Use the command parameter to determine which command to extract, defaulting to "exec"
    $commandKey = $command ? $command : "exec"
    $entryCommand = Get-EntryCommand $selectedEntry $commandKey
    if (!$entryCommand) { return @() }
    $p = Get-ScriptArgs $entryCommand

    return $p
}

function Get-ScriptArgs {
    [OutputType([System.Management.Automation.RuntimeDefinedParameterDictionary])]
    param([scriptblock]$func)
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
        
        foreach ($param in $parameters) {
            if ("$($param.Name)" -eq '$_context') {
                continue
            }
            $dynParam = Get-SingleArg $param
            $paramDictionary.Add($dynParam.Name, $dynParam)
        }
    }
    
    return $paramDictionary
}

function Get-MapEntries(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -or $_ -is [array]
        })]
    $map, 
    $keys, 
    [switch][bool]$flatten = $false,
    [switch][bool]$leafsOnly = $false,
    $separator = ".",
    $reservedKeys = $null
) {
    $results = @()
    
    $completions = Get-CompletionList $map -flatten:$flatten -leafsOnly:$leafsOnly -separator:$separator -reservedKeys $reservedKeys

    foreach ($key in @($keys)) {        
        $found = $completions.GetEnumerator() | ? { $_.key -eq $key }
        if ($found) {
            $results += $found
        }        
    }

    if (!$results) {
        $completions = Get-CompletionList $map -flatten:$flatten -leafsOnly:$leafsOnly -separator:$separator -reservedKeys $reservedKeys
        Write-Verbose "entry '$keys' not found in ($($completions.Keys))"
    }

    return $results
}

function Get-MapEntry(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -or $_ -is [array]
        })]
    $map, 
    $key,
    $separator = "."
) {
    return (Get-MapEntries $map $key -separator $separator).Value
}

# TODO: key should be a hidden property of $entry
function Get-EntryCommand(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -or $_ -is [array] -or $_ -is [scriptblock]
        })]
    $entry, 
    $commandKey = "exec"
) {
    if (!$entry) { throw "entry is NULL" }
    if ($entry -is [scriptblock]) { return $entry }

    if ($entry -is [System.Collections.IDictionary] -or $entry -is [System.Collections.Hashtable]) {
        if (!$entry.$commandKey) {
            throw "Command '$commandKey' not found"
            return $null
        }
        return $entry.$commandKey
    }

    throw "Entry of type $($entry.GetType().Name) is not supported"
    return $null
}

function Invoke-EntryCommand($entry, $key, $ordered = @(), $bound = @{}) {
    $command = Get-EntryCommand $entry $key

    if (!$command) {
        throw "Command '$key' not found"
    }
    if ($command -isnot [scriptblock]) {
        throw "Entry '$key' of type $($command.GetType().Name) is not supported"
    }
    
    if (!$bound) { $bound = @{} }
    if (!$bound._context) { $bound._context = @{} }
    if (!$bound._context.self) { $bound._context.self = $entry }

    return & $command @ordered @bound
}

# function Invoke-Entry(
#     [ValidateScript({
#             $_ -is [string] -or $_ -is [System.Collections.IDictionary]
#         })]
#     $map, 
#     $entry, 
#     $bound
# ) {
#     $map = Import-ConfigMap $map

#     $targets = Get-MapEntries $map $entry
#     Write-Verbose "running targets: $($targets.Key)"

#     @($targets) | % {
#         Write-Verbose "running entry '$($_.key)'"
#         Invoke-EntryCommand -entry $_.value -key "exec" -bound $bound
#     }
# }

function Invoke-Set($entry, $bound = @{}) {
    # use ordered parameters, just in case the handler has different parameter names
    Invoke-EntryCommand $entry "set" -ordered @("", $bound.key, $bound.value) -bound $bound
}

function Invoke-Get($entry, $bound = @{}) {
    # use ordered parameters, just in case the handler has different parameter names
    Invoke-EntryCommand $entry "get" -ordered @("", $bound.options) -bound $bound
}

function Invoke-QBuild {
    [CmdletBinding()]
    param(
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    # ipmo configmap
                    $map = $fakeBoundParameters.map
                    $map = $map ? $map : "./.build.map.ps1"
                    if (!(Test-Path $map)) {
                        return @("init", "help", "list") | ? { $_.startswith($wordToComplete) }
                    }
                    $map = Resolve-ConfigMap $map | % { . $_ } | Validate-ConfigMap
                    return Get-EntryCompletion $map -language "build" @PSBoundParameters
                }
                catch {
                    return "ERROR [-entry]: $($_.Exception.Message) $($_.ScriptStackTrace)"
                }
            })]
        $entry = $null,
        $command = "exec",
        $map = "./.build.map.ps1"
    )
    dynamicparam {
        try {
            $map = Resolve-ConfigMap $map -fallback "./.build.map.ps1" | % { . $_ } | Validate-ConfigMap
            $result = Get-EntryDynamicParam $map $entry $command $PSBoundParameters
            Write-Debug "Dynamic parameters for entry '$entry': $($result.Keys -join ', ')"
            return $result
        }
        catch {
            return "ERROR [dynamic]: $($_.Exception.Message) $($_.ScriptStackTrace)"
        }
    }

    process {
        if ($entry -eq "help") {
            Write-Host "QBUILD"
            Write-Host "A command line tool to manage build scripts"
            Write-Host ""
            Write-Host "Usage:"
            Write-Host "qbuild <your-script-name>"
            return
        }
        if ($entry -eq "list") {
            $map = Resolve-ConfigMap $map -fallback "./.build.map.ps1" | % { . $_ }
            if (!$map) {
                $invocation = $MyInvocation
                Write-Help -invocation $invocation -mapPath "./.build.map.ps1"
                return
            }
            Write-MapHelp -map $map -invocation $MyInvocation
            return
        }
        if ($entry -eq "init") {
            $loadedMap = Resolve-ConfigMap $map -ErrorAction Ignore | % { . $_ }
            if (!$loadedMap) {
                if ($map -isnot [string]) {
                    throw "Map appears to be an object, not a file"
                }
                if ((Test-Path $map)) {
                    throw "map file '$map' already exists"
                }

                Initialize-BuildMap -file $map

                return
            }
            else {
                $completionList = Get-CompletionList $loadedMap -reservedKeys $languages.build.reservedKeys
                if ($completionList.Keys -notcontains "init") {
                    throw "map file '$map' already exists"
                }
                else {
                    # continue with executing "init" command
                }
            }
             
        }

        $map = Resolve-ConfigMap $map -fallback "./.build.map.ps1" -ErrorAction Ignore | % { . $_ }
        if (!$map) {
            $invocation = $MyInvocation
            $commandName = $invocation.Statement
            
            Write-Help -invocation $invocation -mapPath "./.build.map.ps1"
            return
        }

        # If no entry is provided, list all available scripts
        if (-not $entry) {           
            Write-MapHelp -map $map -invocation $MyInvocation
            return
        }

        $targets = Get-MapEntries $map $entry
        Write-Verbose "running targets: $($targets.Key)"

        @($targets) | % {
            Write-Verbose "running entry '$($_.key)'"
            # FIXME: we already have the entry in $_.value, we know ITs own key, but we don't want to search for this key inside this object
            # we should pass null instead?
            #Invoke-EntryCommand -entry $_.value -key $_.Key $bound
            $bound = $PSBoundParameters
            Invoke-EntryCommand -entry $_.value -key $command -bound $bound
        }
    
    }
}

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
                    $map = $map ? $map : "./.configuration.map.ps1"
                    if (!(Test-Path $map)) {
                        return @("init", "help", "list") | ? { $_.startswith($wordToComplete) }
                    }
                    $map = $map -is [IDictionary] ? $map : (Resolve-ConfigMap $map | % { . $_ } | Validate-ConfigMap)
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
                    $map = Resolve-ConfigMap $map -fallback "./.configuration.map.ps1" | % { . $_ } | Validate-ConfigMap
                    $entry = $fakeBoundParameters.entry
                    $entry = Get-MapEntry $map $entry
                    if (!$entry) {
                        throw "entry '$entry' not found"
                    }
                    $options = Get-CompletionList $entry -listKey "options" -reservedKeys $languages.conf.reservedKeys
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
            $map = Resolve-ConfigMap $map -fallback "./.configuration.map.ps1" | % { . $_ } | Validate-ConfigMap
            return Get-EntryDynamicParam $map "$entry.$command" $PSBoundParameters
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

        $map = $map -is [System.Collections.IDictionary] ? $map : (Resolve-ConfigMap $map | % { . $_ } | Validate-ConfigMap)

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

                $submodule = $map.$module
                if (!$submodule) {
                    throw "module '$module' not found"
                }
        
                $optionKey = $value
                $options = Get-CompletionList $subEntry -listKey "options" -reservedKeys $languages.conf.reservedKeys
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
                    $entries = (Get-CompletionList $map -reservedKeys $languages.conf.reservedKeys).Keys 
                }

                foreach ($entry in @($entries)) {
                    try {
                        $subEntry = $map.$entry

                        $options = Get-CompletionList $subEntry -listKey "options" -reservedKeys $languages.conf.reservedKeys
                
                        $bound = $PSBoundParameters
                        $bound.options = $options
                
                        $value = Invoke-Get $subEntry -bound $bound
                
                        $result = ConvertTo-MapResult $value $entry $subEntry $options
                        $result | Write-Output
                    }
                    catch {
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

function Initialize-ConfigMap([Parameter(Mandatory = $true)] $file) {
    if (Test-Path $file) {
        throw "map file '$file' already exists"
    }

    $defaultConfig = Get-Content $PSScriptRoot/samples/_default/.configuration.map.ps1
    Write-Host "Initializing configmap file '$file'"
    $defaultConfig | Out-File $file

    $fullPath = (Get-Item $file).FullName
    $dir = Split-Path $fullPath -Parent
    $defaultUtils = Get-Content $PSScriptRoot/samples/_default/.config-utils.ps1
    $defaultUtils | Out-File (Join-Path $dir ".config-utils.ps1")
}


function Initialize-BuildMap([Parameter(Mandatory = $true)] $file) {
    if (Test-Path $file) {
        throw "map file '$file' already exists"
    }

    $defaultConfig = Get-Content $PSScriptRoot/samples/_default/.build.map.ps1
    Write-Host "Initializing buildmap file '$file'"
    $defaultConfig | Out-File $file
}

#region hierarchy

function Test-IsParentEntry {
    <#
    .SYNOPSIS
        Determines if an entry is a parent container (has nested commands) or a leaf (executable command)
    .PARAMETER Entry
        The map entry to test
    .PARAMETER ListKey
        The key used to identify nested lists (default: "list")
    .PARAMETER ReservedKeys
        Array of reserved keys that should be skipped during processing
    .OUTPUTS
        [PSCustomObject] with IsParent (bool) and HasExplicitList (bool) properties
    #>
    param(
        $Entry,
        $ListKey = "list",
        $ReservedKeys = @("options", "exec", "list")
    )
    
    # If entry is not a hashtable, it's a leaf (scriptblock or other)
    if ($Entry -isnot [System.Collections.IDictionary]) {
        return [PSCustomObject]@{
            IsParent        = $false
            HasExplicitList = $false
        }
    }
    
    # Check for explicit list key (traditional nested structure)
    if ($Entry.$ListKey) {
        return [PSCustomObject]@{
            IsParent        = $true
            HasExplicitList = $true
        }
    }
    
    # Check if entry contains nested commands (hashtables or scriptblocks)
    $hasNestedCommands = $false
    foreach ($subKvp in $Entry.GetEnumerator()) {
        if ($subKvp.Key -in $reservedKeys -or $subKvp.Key -eq $ListKey) {
            continue
        }
        if ($subKvp.Value -is [System.Collections.IDictionary] -or $subKvp.Value -is [scriptblock]) {
            $hasNestedCommands = $true
            break
        }
    }
    
    return [PSCustomObject]@{
        IsParent        = $hasNestedCommands
        HasExplicitList = $false
    }
}

#endregion

#region help
function Write-MapHelp {
    param([System.Collections.IDictionary]$map, $invocation, [ValidateSet("build", "conf")]$language = "build")
    $commandName = $invocation.InvocationName
    $scripts = Get-CompletionList $map -reservedKeys $languages.$language.reservedKeys
    
    # Calculate max command name length for alignment
    $maxNameLength = ($scripts.Keys | Measure-Object -Property Length -Maximum).Maximum
    $maxNameLength = [Math]::Max($maxNameLength, 12) # Minimum width
    
    Write-Host ""
    Write-Host "$($commandName.ToUpper())" -ForegroundColor Cyan
    Write-Host "A command line tool to manage $language scripts" -ForegroundColor Gray
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "    $commandName <COMMAND> [OPTIONS]" -ForegroundColor White
    Write-Host ""
    Write-Host "COMMANDS:" -ForegroundColor Yellow
    
    # Sort scripts alphabetically
    $sortedScripts = $scripts.GetEnumerator() | Sort-Object Name
    
    foreach ($item in $sortedScripts) {
        $name = $item.Name
        $script = $item.Value
        try {
            $entry = Get-EntryCommand $script
        }
        catch {
            $entry = $null
        }
        $args = $entry ? (Get-ScriptArgs $entry) : @{}
        
        # Format command name with proper padding
        $paddedName = $name.PadRight($maxNameLength)
        
        # Get description
        $description = ""
        if ($script -is [System.Collections.IDictionary] -and $script.description) {
            $description = $script.description
        }
        
        $argList = $args.Keys | % { "-$($_)" }
        $paramInfo = ($argList -join " ")
                
        Write-Host "    " -NoNewline
        Write-Host "$paddedName" -ForegroundColor Green -NoNewline
        if ($paramInfo) {
            Write-Host " [$paramInfo]" -ForegroundColor DarkGray -NoNewline
        }
        Write-Host "  $description" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "    $commandName build" -ForegroundColor White
    Write-Host "    $commandName test" -ForegroundColor White
    Write-Host "    $commandName list" -ForegroundColor White
    Write-Host ""
    Write-Host "Use '$commandName help' for more information about this tool." -ForegroundColor Gray
}

function Write-Help {
    param($invocation, [string]$mapPath)
    $commandName = $invocation.Statement
    
    Write-Host "No build map file found at '$mapPath'"
    Write-Host ""
    Write-Host "To create a new build map file, run:"
    Write-Host "  $commandName init"
    Write-Host ""
    Write-Host "This will create a sample $mapPath file with basic build scripts."
}

#endregion


Set-Alias -Name "qbuild" -Value "Invoke-QBuild" -Force
Set-Alias -Name "qconf" -Value "Invoke-QConf" -Force