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

    if ($module -is [System.Collections.IDictionary]) {
        if (!$module.$commandKey) {
            throw "Command '$commandKey' not found"
        }
        return $module.$commandKey
    }

    throw "Module of type $($module.GetType().Name) is not supported"
}

function Invoke-ModuleCommand($module, $key, $bound = @{}) {
    $command = Get-ModuleCommand $module $key

    if (!$command) {
        throw "Command '$key' not found"
    }
    if ($command -isnot [scriptblock]) {
        throw "Module '$key' of type $($command.GetType().Name) is not supported"
    }
    
    if (!$bound) { $bound = @() }
    if (!$bound.context) { $bound.context = @{} }
    if (!$bound.context.self) { $bound.context.self = $module }

    return & $command @bound
}

function Invoke-Set($module) {
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

function Get-ModuleDynamicParam($map, $key, $bound) {
    if (!$key) { return @() }

    if ($map -is [string]) {
        $mapFile = $map
        $map = . $mapFile
    }
    if (!$map) {
        throw "failed to load map from $mapFile"
    }

    $bound = $PSBoundParameters

    $selectedModule = Get-MapModule $map $key
    if (!$selectedModule) { return @() }
    $command = Get-ModuleCommand $selectedModule
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

        Invoke-ModuleCommand -module $_.value -key $_.Key $bound
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
                # ipmo configmap
                $map = $fakeBoundParameters.map 
                if (!$map) { $map = "./.build.map.ps1" }
                return Get-ModuleCompletion $map @PSBoundParameters
            })]
        $module = $null,
        $map = "./.build.map.ps1"
    )
    DynamicParam {
        # ipmo configmap
        return Get-ModuleDynamicParam $map $module $PSBoundParameters
    }

    process {
        Invoke-Module $map $module $PSBoundParameters
    }
}

function qconf {
    [CmdletBinding()]
    param(
        [ValidateSet("set", "get", "list")]
        $command,
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    $map = $fakeBoundParameters.map
                    if (!$map) { $map = "./.configuration.map.ps1" }
                    
                    return Get-ModuleCompletion $map @PSBoundParameters
                }
                catch {
                    return "ERROR: $($_.Exception.Message) $($_.ScriptStackTrace)"
                }
            })] 
        $module = $null,
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
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
                    return "ERROR: $($_.Exception.Message) $($_.ScriptStackTrace)"
                }
            
            })] 
        $value = $null,
        $map = "./.configuration.map.ps1"
    )

    DynamicParam {
        # ipmo configmap
        try {
            if (!$module) {
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
            Write-Host "ERROR: $($_.Exception.Message) $($_.ScriptStackTrace)"
            throw
        }
    }

    process {
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
                $bound["key"] = $optionKey
                $bound["value"] = $optionValue
                
                Invoke-ModuleCommand $submodule $command -bound $bound
            }
            "get" {
                $options = Get-CompletionList $submodule -listKey "options"
                
                $bound = $PSBoundParameters
                
                $value = Invoke-ModuleCommand $submodule $command -bound $bound

                $result = $null

                if ($value -is [Hashtable]) {
                    $hash = @{ Path = "$moduleName/$subPath" }
                    $hash += $value
                    $result = $hash
                }
                else {
                    $result = @{ Path = "$moduleName/$subPath"; Value = $value }
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
                        $isvalid = Invoke-Command $module.validate -ArgumentList @($path, $optionvalue, $result.Active)
                    }
                }

                $result = [PSCustomObject]@{
                    Path    = $result.Path
                    Value   = $result.Value
                    Active  = $result.Active
                    Options = $result.Options
                    IsValid = $isvalid
                } 
                # if ($isvalid -ne "?") {
                #     $result | Add-Member -MemberType NoteProperty -Name IsValid -Value $isvalid
                # }
                $result | Write-Output
            }
            Default {
                throw "command '$command' not supported"
            }
        }
        
    }
}