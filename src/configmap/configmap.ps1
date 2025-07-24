$reservedKeys = @("options", "exec")
function Get-CompletionList($map,
    [switch][bool]$flatten = $true,
    $separator = ".", 
    $groupMarker = "*", 
    $listKey = "list") {
    
    if (!$map) {
        throw "map is null"
    }

    $result = [ordered]@{}
    
    $l = $map
    if ($map.$listKey) {
        $l = $map.$listKey
    }

    if ($l -is [scriptblock]) {
        $l = Invoke-Command -ScriptBlock $l
    }
    
    if ($l -is [System.Collections.IDictionary]) {
        foreach ($kvp in $l.GetEnumerator()) {
            if ($kvp.key -in $reservedKeys -or $kvp.key -eq $listKey) {
                continue
            }
            $module = $kvp.value
            if ($module.$listKey) {
                if ($flatten) {
                    $result["$($kvp.key)$groupMarker"] = $module
                }

                $submodules = Get-CompletionList $module -listKey $listKey -flatten:$flatten
                foreach ($sub in $submodules.GetEnumerator()) {
                    
                    $subKey = $sub.Key
                    if (!$flatten) {
                        $subKey = "$($kvp.key)$separator$($sub.Key)"
                    }
                    $result[$subKey] = $sub.value
                }
            }
            else {
                $singleKey = "$($kvp.key)"
                $result.$singleKey = $module
            }
        }

        return $result
    }
    elseif ($l -is [array]) {
        $submodules = $l | % { $r = [ordered]@{} } { $r[$_] = $_ } { $r }
    }
    elseif ($l -is [System.Collections.IDictionary]) {
        $submodules = $l
    }
    
    if ($map -is [array]) {
        $l = $map
        $submodules = $l | % { $r = [ordered]@{} } { $r[$_] = $_ } { $r }
    }

    if ($submodules) {
        foreach ($sub in $submodules.GetEnumerator()) {
            if ($sub.key -in $reservedKeys -or $sub.key -eq $listKey) {
                continue
            }
            $result[$sub.key] = $sub.value
        }
        return $result
    }

    throw "$($map.GetType().FullName) type not supported"
}

function Get-ValuesList($map) {
    if (!$map.options) {
        throw "map doesn't have 'options' entry"
    }

    return Get-CompletionList $map.options
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

function Get-MapModules($map, $keys, [switch][bool]$flatten = $true) {
    $list = Get-CompletionList $map -flatten:$flatten
    
    $found = $list.GetEnumerator() | ? { $_.key -in @($keys) }

    if (!$found) {
        Write-Verbose "module '$keys' not found in ($($list.Keys))"
    }
    return $found
}

function Get-MapModule($map, $key) {
    return (Get-MapModules $map $key).Value
}

# TODO: key should be a hidden property of $module
function Get-ModuleCommand($module, $commandKey = "exec") {
    if (!$module) { throw "module is NULL" }
    if ($module -is [scriptblock]) { return $module }

    if ($module -is [System.Collections.IDictionary] -or $module -is [System.Collections.Hashtable]) {
        if (!$module.$commandKey) {
            throw "Command '$commandKey' not found"
        }
        return $module.$commandKey
    }

    throw "Module of type $($module.GetType().Name) is not supported"
}

function Invoke-ModuleCommand($module, $key, $ordered = @(), $bound = @{}) {
    $command = Get-ModuleCommand $module $key

    if (!$command) {
        throw "Command '$key' not found"
    }
    if ($command -isnot [scriptblock]) {
        throw "Module '$key' of type $($command.GetType().Name) is not supported"
    }
    
    if (!$bound) { $bound = @{} }
    if (!$bound.context) { $bound.context = @{} }
    if (!$bound.context.self) { $bound.context.self = $module }

    return & $command @ordered @bound
}

function Invoke-Set($module, $bound = @{}) {
    # use ordered parameters, just in case the handler has different parameter names
    Invoke-ModuleCommand $module "set" -ordered @("", $bound.key, $bound.value) -bound $bound
}

function Invoke-Get($module, $bound = @{}) {
    # use ordered parameters, just in case the handler has different parameter names
    Invoke-ModuleCommand $module "get" -ordered @("", $bound.options) -bound $bound
}

function Get-ModuleCompletion($map, $commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters) {
    if ($map -is [string]) {
        if (!(test-path $map)) {
            throw "map file '$map' not found"
        }
        $map = . $map
    }

    $list = Get-CompletionList $map
    return $list.Keys | ? { $_.startswith($wordToComplete) }
}

function Get-ModuleDynamicParam($map, $key, $command, $bound) {
    if (!$key) { return @() }

    if ($map -is [string]) {
        $mapFile = $map
        $map = . $mapFile
    }

    if (!$map) {
        throw "failed to load map from $mapFile"
    }

    #$bound = $PSBoundParameters

    $selectedModule = Get-MapModule $map $key
    if (!$selectedModule) { return @() }
    $command = Get-ModuleCommand $selectedModule $command
    if (!$command) { return @() }
    $p = Get-ScriptArgs $command

    return $p
}

function Invoke-Module($map, $module, $bound) {
    if ($map -is [string]) {
        $map = . $map
    }

    $targets = Get-MapModules $map $module
    write-verbose "running targets: $($targets.Key)"

    @($targets) | % {
        Write-Verbose "running module '$($_.key)'"
        # FIXME: we already have the module in $_.value, we know ITs own key, but we don't want to search for this key inside this object
        # we should pass null instead?
        #Invoke-ModuleCommand -module $_.value -key $_.Key $bound
        Invoke-ModuleCommand -module $_.value -key "exec" -bound $bound
    }
}

function qrun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $map,
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                # ipmo configmap
                return Get-ModuleCompletion $map @PSBoundParameters
            })]
        [Parameter(Mandatory = $true, Position = 1)]
        $module = $null
    )
    DynamicParam {
        # ipmo configmap
        return Get-ModuleDynamicParam $map $module $PSBoundParameters
    }

    process {
        Invoke-Module $map $module $PSBoundParameters
    }
}

function qbuild {
    [CmdletBinding()]
    param(
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    # ipmo configmap
                    $map = $fakeBoundParameters.map
                    if (!$map) { $map = "./.build.map.ps1" }
                    if (!(test-path $map)) {
                        return @("init", "help") | ? { $_.startswith($wordToComplete) }
                    }
                    return Get-ModuleCompletion $map @PSBoundParameters
                }
                catch {
                    return "ERROR [-module]: $($_.Exception.Message) $($_.ScriptStackTrace)"
                }
            })]
        $module = $null,
        $command = "exec",
        $map = "./.build.map.ps1"
    )
    DynamicParam {
        try {
            # ipmo configmap
            if (!$map) { $map = "./.build.map.ps1" }
            return Get-ModuleDynamicParam $map $module $command $PSBoundParameters
        }
        catch {
            return "ERROR [dynamic]: $($_.Exception.Message) $($_.ScriptStackTrace)"
        }
    }

    process {
        if ($module -eq "help") {
            Write-Host "QBUILD"
            Write-Host "A command line tool to manage build scripts"
            Write-Host ""
            Write-Host "Usage:"
            write-host "qbuild <your-script-name>"
            return
        }
        if ($module -eq "init") {
            if (!$map) { $map = "./.build.map.ps1" }
            if ($map -is [string]) {
                if ((test-path $map)) {
                    throw "map file '$map' already exists"
                }
            }
            else {
                throw "Map appears to be an object, not a file"
            }

            init-buildMap -file $map

            return
        }

        if ($map -is [string]) {
            $map = . $map
        }

        $targets = Get-MapModules $map $module
        write-verbose "running targets: $($targets.Key)"

        @($targets) | % {
            Write-Verbose "running module '$($_.key)'"
            # FIXME: we already have the module in $_.value, we know ITs own key, but we don't want to search for this key inside this object
            # we should pass null instead?
            #Invoke-ModuleCommand -module $_.value -key $_.Key $bound
            $bound = $PSBoundParameters
            Invoke-ModuleCommand -module $_.value -key $command -bound $bound
        }
    
    }
}

function qconf {
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
                    if (!$map) { $map = "./.configuration.map.ps1" }
                    
                    return Get-ModuleCompletion $map @PSBoundParameters
                }
                catch {
                    return "ERROR [-module]: $($_.Exception.Message) $($_.ScriptStackTrace)"
                }
            })] 
        $module = $null,
        
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    if ($fakeBoundParameters.command -in @("init", "help")) {
                        return @()
                    }

                    $map = $fakeBoundParameters.map
                    if (!$map) { $map = "./.configuration.map.ps1" }
                    if ($map -is [string]) {
                        if (!(test-path $map)) {
                            throw "map file '$map' not found"
                        }
                        $map = . $map
                    }
                    $module = $fakeBoundParameters.module
                    $entry = Get-MapModule $map $module
                    if (!$entry) {
                        throw "module '$module' not found"
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
    ## this assumes that -module and -command are already provided
    DynamicParam {
        # ipmo configmap
        try {
            if ( !$module) {
                return @()
            }
            if (!$map) { $map = "./.configuration.map.ps1" }
            if ($map -is [string]) {
                if (!(test-path $map)) {
                    throw "map file '$map' not found"
                }
                $map = . $map
            }
            return Get-ModuleDynamicParam $map "$module.$command" $PSBoundParameters
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
            write-host "qconf -module <module> -command <command> -value <value>"
            return
        }
        if ($command -eq "init") {
            if (!$map) { $map = "./.configuration.map.ps1" }
            if ($map -is [string]) {
                if ((test-path $map)) {
                    throw "map file '$map' already exists"
                }
            }
            else {
                throw "Map appears to be an object, not a file"
            }

            init-configmap -file $map

            return
        }

        if ($map -is [string]) {
            if (!(test-path $map)) {
                throw "map file '$map' not found"
            }
            $map = . $map
        }
        if (!$map) {
            throw "Failed to load map"
        }

        Write-Verbose "module=$module command=$command"

        $submodule = $map.$module
        if (!$submodule) {
            throw "module '$module' not found"
        }

        switch ($command) {
            "set" {
                $optionKey = $value
                $options = Get-CompletionList $submodule -listKey "options"
                $optionValue = $options.$optionKey

                $bound = $PSBoundParameters
                $bound.key = $optionKey
                $bound.value = $optionValue
                Invoke-Set $submodule -ordered "", $optionValue, $optionKey -bound $bound
            }
            "get" {
                $options = Get-CompletionList $submodule -listKey "options"
                
                $bound = $PSBoundParameters
                $bound.options = $options
                
                $value = Invoke-Get $submodule -bound $bound
                
                $result = ConvertTo-MapResult $value $submodule $options
                $result | Write-Output
            }
            Default {
                throw "command '$command' not supported"
            }
        }
        
    }
}

function ConvertTo-MapResult($value, $module, $options, $validate = $true) {
    $result = $null
    if ($value -is [Hashtable]) {
        $hash = @{
            Path = "$moduleName/$subPath"
        }
        $hash += $value
        
        $result = $hash
    }
    else {
        $result = @{ 
            Path  = "$moduleName/$subPath"
            Value = $value
        }
    }

    if (!$result.Active) {
        $result.Active = $options.keys | where { $options.$_ -eq $value }
    }
    $result.Options = $options.keys

    $isvalid = "?"
    if ($validate -and $module.validate) {
        if (!$result.Active) {
            write-host "no active option found for $moduleName/$subPath"
            $isvalid = $null
        }
        else {
            $optionvalue = $options.$($result.Active)
            $isvalid = Invoke-ModuleCommand $module validate -ordered @($path, $optionvalue, $result.Active)
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

function init-configmap([Parameter(Mandatory = $true)] $file) {
    if (test-path $file) {
        throw "map file '$file' already exists"
    }

    $defaultConfig = get-content $PSScriptRoot/samples/_default/.configuration.map.ps1
    write-host "Initializing configmap file '$file'"
    $defaultConfig | Out-File $file

    $fullPath = (get-item $file).FullName
    $dir = Split-Path $fullPath -Parent
    $defaultUtils = get-content $PSScriptRoot/samples/_default/.config-utils.ps1
    $defaultUtils | Out-File (Join-Path $dir ".config-utils.ps1")
}


function init-buildMap([Parameter(Mandatory = $true)] $file) {
    if (test-path $file) {
        throw "map file '$file' already exists"
    }

    $defaultConfig = get-content $PSScriptRoot/samples/_default/.build.map.ps1
    write-host "Initializing buildmap file '$file'"
    $defaultConfig | Out-File $file
}