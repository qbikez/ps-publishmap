. "$PSScriptRoot\includes.ps1"

function convertto-object {
param([Parameter(ValueFromPipeline=$true)]$hash)
    return new-object -type pscustomobject -Property $hash
}

function flatten-by($p, $name, $level, $propname) {
    $r = @()
    if (!($p -is [System.Collections.IDictionary])) {
        return $r;
    }
    #0..$level | % { write-host " " -NoNewline }
    #write-host "checking $name" level $level
    if ($p.$propname -ne $null) {
        #write-host "checking level of $name"
        $r += @(@{path = $p._fullpath; value = $p; level=$level } | convertto-object)
    }
    if ($level -ge 3) { return $r }
            
    foreach($subp in get-propertynames $p) {
            if ($subp -eq "project") { continue }
            $r += flatten-by $p.$subp $subp ($level+1) $propname
    }  

    return $r

}



Describe "parse publish map" {
  $maps = @(gci "$PSScriptRoot\input" -filter "publishmap.*.config.ps1" | % { 
   @{ file=$_.name; item = $_ }
  })

    Context "When artificial properties are added" {
        $cases = @()
          foreach($f in $maps) {
            $map = import-map $f.item
            $flat = flatten-by $map "root" 0 "_level"
            $flat | Should Not BeNullOrEmpty    
            $cases += $flat | % { @{ 
                file = $f.file
                item = $f.item
                path = $_.path
                value = $_.value 
                level = $_.level
            } }
          }

          <#
        It "flat should be valid" -TestCases $cases { 
            param([string]$file, $item)
            $map = import-publishmap $item
            $flat = flatten-by $map "root" 0 "_level"
            $flat | Should Not BeNullOrEmpty
        }#>
      It "_level should be <level> for '<file>':'<path>'" -TestCases $cases {
        param([string]$file, $item, $path, $value, $level)
            $value._level | Should Be $level
        
      }
    }  
}


Describe "parse publish map 2" {
  $maps = @(gci "$PSScriptRoot\input" -filter "publishmap.*.config.ps1" | % { 
   @{ file=$_.name; item = $_ }
  })
  Context "When map is parsed" {
      It "Should return a valid map for '<file>'" -TestCases $maps {
        param([string]$file, $item)
        $map = import-publishmap $item
        $map | Should Not BeNullOrEmpty     
      }
  }
  
  
}