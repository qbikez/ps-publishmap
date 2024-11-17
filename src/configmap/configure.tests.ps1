BeforeAll {
    . $PSScriptRoot/.config-utils.ps1

    function Get-CompletionList($modules) {
        $result = [ordered]@{}

        $l = $modules
        if ($modules.list) {
            $l = $modules.list
        }
        if ($l -is [scriptblock]) {
            $submodules = Invoke-Command -ScriptBlock $l
        }
        elseif ($l -is [array]) {
            $submodules = $l | % { $r = @{} } { $r[$_] = $_ } { $r }
        }
        
        if ($submodules) {
            foreach ($sub in $submodules.GetEnumerator()) {
                $result[$sub.key] = $sub.value
            }
            return $result
        }

        if ($modules -isnot [hashtable] -and $modules -isnot [System.Collections.Specialized.OrderedDictionary]) {
            throw "$($modules.GetType().FullName) type not supported"
        }

        foreach ($kvp in $modules.GetEnumerator()) {
            $module = $kvp.value
            if ($module.list) {
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
}


Describe 'configuration map' -ForEach @(
    @{
        Name = "simple list"
        Map  = @("item1", "item2")
        Keys = @("item1", "item2")
    }
    @{
        Name = "simple map"
        Map  = [ordered]@{
            "key1" = @{ id = "a" }
            "key2" = @{ id = "b" }
        }
        Keys = @("key1", "key2")
    }
    @{
        Name = "one-level simple list"
        Map  = [ordered]@{
            "key1" = @{
                list = ("a", "b")
            }
            "key2" = @{ id = "b" }
        }
        Keys = @("key1*", "a", "b", "key2")
    }
) {
    Describe "<name>" {
        It '<name> resolves to list of keys' {
            $result = Get-CompletionList $map
            $result.Keys | Should -Be $keys
        }
    }
}