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

function Get-DynamicParam($map) {
    
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