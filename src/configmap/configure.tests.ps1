BeforeAll {
    . $PSScriptRoot/.config-utils.ps1

    function Get-CompletionList($modules) {
        if ($modules -is [array]) {
            return $modules
        }

        $result = [ordered]@{}
        foreach ($kvp in $modules.GetEnumerator()) {
            $module = $kvp.value
            if ($module.list) {
                $groupKey = "$($kvp.key)*"
                $result.$groupKey = $module
                
                if ($module.list -is [scriptblock]) {
                    $submodules = Invoke-Command -ScriptBlock $module.list
                } elseif ($module.list -is [array]) {
                    $submodules = $module.list | % { $r = @{} } { $r[$_] = $_ } { $r }
                }

                foreach ($sub in $submodules.GetEnumerator()) {
                    $result[$sub.key] = $sub.value
                }
            }
            else {
                $groupKey = "$($kvp.key)"
                $result.$groupKey = $module
            }
        }
        return $result
    }
}

Describe 'configuration map' {
    Describe "simple list" {
        BeforeAll {
            $map = @("item1", "item2")
        }
        It 'resolves to list of keys' {
            $result = Get-CompletionList $map
            $result | Should -Be @("item1", "item2")
        }
    }

    Describe "simple map" {
        BeforeAll {
            $map = [ordered]@{ 
                "key1" = @{ id = "a" }
                "key2" = @{ id = "b" }
            }
        }
        It 'resolves to list of keys' {
            $result = Get-CompletionList $map
            $result.Keys | Should -be @("key1", "key2")
        }
    }

    Describe "one-level simple list" {
        BeforeAll {
            $map = [ordered]@{ 
                "key1" = @{ 
                    list = ("a", "b")
                }
                "key2" = @{ id = "b" }
            }
        }
        It 'resolves to list of keys' {
            $result = Get-CompletionList $map
            $result.Keys | Should -be @("key1*", "a", "b", "key2")
        }
    }
}