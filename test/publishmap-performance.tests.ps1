. "$PSScriptRoot\includes.ps1"

function convertto-array([Parameter(ValueFromPipeline=$true)] $enumerable, [switch][bool]$flatten = $true) {
    $a = @()
    if ($enumerable -is [hashtable]) {
        $enumerable = $enumerable.Values
    }
    
    if ($enumerable -is [System.Collections.IEnumerable]) {
        if (!$flatten) {
            $a += $enumerable.Values        
        } else {
            foreach($val in $enumerable.GetEnumerator()) {
                if ($val -is [System.Collections.IEnumerable]) {
                    $a += convertto-array $val -flatten:$flatten
                }
                else {
                    $a += $val
                }
            }
        }

        return $a
    }
    else {
        throw "don't know how to convert type $($enumerable.GetType().FullName) to array"
    }
}


Describe "parse publish map performance" {
    $maps = @(gci "$PSScriptRoot\input\performance" -filter "publishmap.*.config.ps1"| % { 
            @{ file=$_.name; item = $_ }
        })

    Context "When map is parsed" {
        It "Should take reasonable time for file '<file>'" -TestCases $maps {
            param([string]$file, $item)
            $global:perfcounters = $null
            $r = Measure-command {
                try {
                    $map = import-publishmap $item -Verbose
                } catch {
                    write-error $_.scriptstacktrace
                    throw $_
                }
            }
            if ($global:perfcounters) {
                $arr = $global:perfcounters | convertto-array 
                $arr | sort elapsed | format-table -Wrap  | out-string | write-host
            }
            $r.TotalSeconds | Should BeLessThan 10
            
        }
    }
    
}

