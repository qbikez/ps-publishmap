BeforeAll {
    . $PSScriptRoot/.config-utils.ps1

    function Get-CompletionList($modules) {
        $result = [ordered]@{}

        $l = $modules
        if ($modules.list) {
            $l = $modules.list
        }
        
        if ($l -is [System.Collections.IDictionary]) {
            foreach ($kvp in $l.GetEnumerator()) {
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

        if ($l -is [scriptblock]) {
            $submodules = Invoke-Command -ScriptBlock $l
        }
        elseif ($l -is [array]) {
            $submodules = $l | % { $r = @{} } { $r[$_] = $_ } { $r }
        }
        elseif ($l -is [System.Collections.IDictionary]) {
            $submodules = $l
        }
        
        if ($modules -is [array]) {
            $l = $modules
            $submodules = $l | % { $r = @{} } { $r[$_] = $_ } { $r }
        }

        if ($submodules) {
            foreach ($sub in $submodules.GetEnumerator()) {
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
}

Describe "map parsing" {

    Describe 'keys' -ForEach @(
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
        @{
            Name = "config-like"
            Map  = [ordered]@{
                "db"      = @{
                    options = @{
                        "local"  = @{
                            connectionString = "blah"
                        }
                        "remote" = @{
                            connectionString = "boom"
                        }
                    }
                }
                "secrets" = @{
                    list = @{
                        connectionString = @{
                            "local"  = "blah"
                            "remote" = "boom"
                        }
                        keyVault         = @{
                            "local"  = "blah"
                            "remote" = "boom"
                        }
                    }
                }
            }
            Keys = @("db", "secrets*", "connectionString", "keyVault")
        }
    ) {
        Describe "<name>" {
            It '<name> => keys' {
                $result = Get-CompletionList $map
                $result.Keys | Should -Be $keys
            }
        }
    }

    Describe "values" -ForEach @(
        @{
            Name   = "options value"
            Map    = @{
                options = @{
                    "a" = 1
                    "b" = 2
                }
            }
            Values = @("a", "b")
        }
        @{
            Name   = "options func"
            Map    = @{
                options = {
                    return @{ 
                        "a" = 1
                        "b" = 2
                    }
                }
            }
            Values = @("a", "b")
        }
    ) {
        Describe "<name>" {
            It "<name> => options" {
                $result = Get-ValuesList $map
                $result.Keys | Should -Be $Values
            }
        }
    }
}