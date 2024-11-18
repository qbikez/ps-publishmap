$reservedKeys = @("options", "exec", "list")
function Get-CompletionList($modules) {
    $result = [ordered]@{}
    $listKey = "list"

    $l = $modules
    if ($modules.$listKey) {
        $l = $modules.$listKey
    }
    
    if ($l -is [System.Collections.IDictionary]) {
        foreach ($kvp in $l.GetEnumerator()) {
            $module = $kvp.value
            if ($module.$listKey) {
                $groupKey = "$($kvp.key)*"
                $result.$groupKey = $module
            
                $submodules = Get-CompletionList $module
                $result += $submodules
            }
            else {
                $groupKey = "$($kvp.key)"
                $result.$groupKey = $module
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

function Get-DynamicParam($map) {
    
}

function Invoke-ModuleCommand($module, $key, $context = @{}) {
    $context.self = $module
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