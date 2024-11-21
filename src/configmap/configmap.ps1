$reservedKeys = @("options", "exec", "list")
function Get-CompletionList($modules, [switch][bool]$flatten = $true, $separator = ".", $groupMarker = "*") {
    if (!$modules) {
        throw "modules is null"
    }

    $result = [ordered]@{}
    $listKey = "list"

    $l = $modules
    if ($modules.$listKey) {
        $l = $modules.$listKey
    }
    
    if ($l -is [System.Collections.IDictionary]) {
        foreach ($kvp in $l.GetEnumerator()) {
            if ($kvp.key -in $reservedKeys) {
                continue
            }
            $module = $kvp.value
            if ($module.$listKey) {
                $groupKey = "$($kvp.key)$groupMarker"
                $result.$groupKey = $module
            
                $submodules = Get-CompletionList $module
                foreach($sub in $submodules.GetEnumerator()) {
                    
                    $subKey = $sub.Key
                    if (!$flatten) {
                        $subKey = "$groupKey$separator$($sub.Key)"
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

    if ($l -is [scriptblock]) {
        $submodules = Invoke-Command -ScriptBlock $l
    }
    elseif ($l -is [array]) {
        $submodules = $l | % { $r = [ordered]@{} } { $r[$_] = $_ } { $r }
    }
    elseif ($l -is [System.Collections.IDictionary]) {
        $submodules = $l
    }
    
    if ($modules -is [array]) {
        $l = $modules
        $submodules = $l | % { $r = [ordered]@{} } { $r[$_] = $_ } { $r }
    }

    if ($submodules) {
        foreach ($sub in $submodules.GetEnumerator()) {
            if ($sub.key -in $reservedKeys) {
                continue
            }
            $result[$sub.key] = $sub.value
        }
        return $result
    }

    throw "$($modules.GetType().FullName) type not supported"
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
        $dynParam = get-single-arg $param
        $paramDictionary.Add($dynParam.Name, $dynParam)
    }
    
    return $paramDictionary
}

function invoke-build {
    [CmdletBinding()]
    param ($target)

    DynamicParam {
        $p = get-script-args $targets.$target

        return $p
    }
    begin {}
    process {
        $p = $PSBoundParameters
        write-host "build $p"
    }
}

function Invoke-ModuleCommand($module, $key, $context = @{}) {
    if (!$context.self) { $context.self = $module }
    if ($module -is [scriptblock]) {
        return Invoke-Command -ScriptBlock $module -ArgumentList @($context)
    }
    if ($module -is [System.Collections.IDictionary]) {
        $commandKey = "exec"
        if (!$module.$commandKey) {
            throw "Command $key.$commandKey not found"
        }
        return Invoke-ModuleCommand $module.$commandKey $key $context
    }
    
    throw "Module $key is not supported"
}