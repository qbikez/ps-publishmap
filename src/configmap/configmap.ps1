#requires -version 7.0

$reservedKeys = @("options", "exec")

function Import-ConfigMap {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ $_ -is [string] -or $_ -is [System.Collections.IDictionary] -or $null -eq $_ })]
        $map,
        [Parameter(Mandatory = $false)]
        $defaultMapFile
    )
    
    # Set default map file if null
    if (!$map) {
        if (!$defaultMapFile) {
            throw "map is null and defaultMapFile is not provided"
        }
        $map = $defaultMapFile 
    }
    
    # Load map from file if it's a string path
    if ($map -is [string]) {
        if (!(Test-Path $map)) {
            throw "map file '$map' not found"
        }
        $map = . $map
    }
    
    # Validate that we have a loaded map
    if (!$map) {
        throw "failed to load map from $defaultMapFile"
    }
    
    return $map
}

function Get-CompletionList {
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [ValidateScript({ 
            # the function do not suppurt strings, but ValidateScript iterates over the array, so for string[] we'll get string items here.
            # see: https://github.com/PowerShell/PowerShell/issues/6185
            $_ -is [System.Collections.IDictionary] -or $_ -is [array] -or $_ -is [scriptblock] -or $_ -is [string]
        })]
        $map,
        [switch][bool]$flatten = $true,
        $separator = ".",
        $groupMarker = "*", 
        $listKey = "list"
    )
    
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
                if ($entry.$listKey) {
                    if ($flatten) {
                        $result["$($kvp.key)$groupMarker"] = $entry
                    }

                    $subEntries = Get-CompletionList $entry -listKey $listKey -flatten:$flatten
                    foreach ($sub in $subEntries.GetEnumerator()) {
                        $subKey = $sub.Key
                        if (!$flatten) {
                            $subKey = "$($kvp.key)$separator$($sub.Key)"
                        }
                        $result[$subKey] = $sub.value
                    }
                }
                else {
                    $result[$kvp.key] = $entry
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
    $commandName, 
    $parameterName, 
    $wordToComplete, 
    $commandAst, 
    $fakeBoundParameters
) {
    $list = Get-CompletionList $map
    return $list.Keys | ? { $_.startswith($wordToComplete) }
}

function Get-ValuesList(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -and $_.options
        })]
    $map
) {
    if (!$map.options) {
        throw "map doesn't have 'options' entry"
    }

    return Get-CompletionList $map.options
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
    $command = Get-EntryCommand $selectedEntry $command
    if (!$command) { return @() }
    $p = Get-ScriptArgs $command

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

    $parameters = $func.AST.ParamBlock.Parameters

    # Add parameter to parameter dictionary and return the object
    $paramDictionary = New-Object `
        -Type System.Management.Automation.RuntimeDefinedParameterDictionary
    
    foreach ($param in $parameters) {
        $dynParam = Get-SingleArg $param
        $paramDictionary.Add($dynParam.Name, $dynParam)
    }
    
    return $paramDictionary
}

function Get-MapEntries(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -or $_ -is [array]
        })]
    $map, 
    $keys, 
    [switch][bool]$flatten = $true
) {
    $list = Get-CompletionList $map -flatten:$flatten
    
    $found = $list.GetEnumerator() | ? { $_.key -in @($keys) }

    if (!$found) {
        Write-Verbose "entry '$keys' not found in ($($list.Keys))"
    }
    return $found
}

function Get-MapEntry(
    [ValidateScript({
            $_ -is [System.Collections.IDictionary] -or $_ -is [array]
        })]
    $map, 
    $key
) {
    return (Get-MapEntries $map $key).Value
}

# TODO: key should be a hidden property of $entry
function Get-EntryCommand($entry, $commandKey = "exec") {
    if (!$entry) { throw "entry is NULL" }
    if ($entry -is [scriptblock]) { return $entry }

    if ($entry -is [System.Collections.IDictionary] -or $entry -is [System.Collections.Hashtable]) {
        if (!$entry.$commandKey) {
            throw "Command '$commandKey' not found"
        }
        return $entry.$commandKey
    }

    throw "Entry of type $($entry.GetType().Name) is not supported"
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
    if (!$bound.context) { $bound.context = @{} }
    if (!$bound.context.self) { $bound.context.self = $entry }

    return & $command @ordered @bound
}

function Invoke-Entry(
    [ValidateScript({
            $_ -is [string] -or $_ -is [System.Collections.IDictionary]
        })]
    $map, 
    $entry, 
    $bound
) {
    $map = Import-ConfigMap $map

    $targets = Get-MapEntries $map $entry
    Write-Verbose "running targets: $($targets.Key)"

    @($targets) | % {
        Write-Verbose "running entry '$($_.key)'"
        Invoke-EntryCommand -entry $_.value -key "exec" -bound $bound
    }
}

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
                        return @("init", "help") | ? { $_.startswith($wordToComplete) }
                    }
                    $map = Import-ConfigMap $map
                    return Get-EntryCompletion $map @PSBoundParameters
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
            $map = Import-ConfigMap $map "./.build.map.ps1"
            return Get-EntryDynamicParam $map $entry $command $PSBoundParameters    
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
        if ($entry -eq "init") {
            if (!$map) { $map = "./.build.map.ps1" }
            if ($map -is [string]) {
                if ((Test-Path $map)) {
                    throw "map file '$map' already exists"
                }
            }
            else {
                throw "Map appears to be an object, not a file"
            }

            Initialize-BuildMap -file $map

            return
        }

        $map = Import-ConfigMap $map "./.build.map.ps1"

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
                    if ($fakeBoundParameters.command -in @("init", "help")) {
                        return @()
                    }
                    $map = $fakeBoundParameters.map
                    $map = Import-ConfigMap $map "./.configuration.map.ps1"
                    
                    return Get-EntryCompletion $map @PSBoundParameters
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
                    $map = Import-ConfigMap $map "./.configuration.map.ps1"
                    $entry = $fakeBoundParameters.entry
                    $entry = Get-MapEntry $map $entry
                    if (!$entry) {
                        throw "entry '$entry' not found"
                    }
                    $options = Get-CompletionList $entry -listKey "options"
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
            $map = Import-ConfigMap $map "./.configuration.map.ps1"
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

        $map = Import-ConfigMap $map "./.configuration.map.ps1"

        Write-Verbose "entry=$entry command=$command"

        $subEntry = $map.$entry
        if (!$subEntry) {
            throw "entry '$entry' not found"
        }

        switch ($command) {
            "set" {
                $submodule = $map.$module
                if (!$submodule) {
                    throw "module '$module' not found"
                }
        
                $optionKey = $value
                $options = Get-CompletionList $subEntry -listKey "options"
                $optionValue = $options.$optionKey

                $bound = $PSBoundParameters
                $bound.key = $optionKey
                $bound.value = $optionValue
                Invoke-Set $subEntry -ordered "", $optionValue, $optionKey -bound $bound
            }
            "get" {
                $options = Get-CompletionList $subEntry -listKey "options"
                
                $bound = $PSBoundParameters
                $bound.options = $options
                
                $value = Invoke-Get $subEntry -bound $bound
                
                $result = ConvertTo-MapResult $value $subEntry $options
                $result | Write-Output
            }
            default {
                throw "command '$command' not supported"
            }
        }
        
    }
}

function ConvertTo-MapResult($value, $entry, $options, $validate = $true) {
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
            Write-Host "no active option found for $entryName/$subPath"
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

Set-Alias -Name "qbuild" -Value "Invoke-QBuild" -Force
Set-Alias -Name "qconf" -Value "Invoke-QConf" -Force