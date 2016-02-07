. "$PSScriptRoot\includes.ps1"

Describe "parse simple map" {
      $m = @{
        settings = @{
            Port = 22
            _strip = $true
        }
        machine_N_ = @{ computername = "machine{N}.cloudapp.net"; Port = "{N}985" }
        abc = @{ ComputerName = "pegaz.legimi.com"; }    
      }
      $map = import-mapobject $m -verbose
      
      Context "when map is imported" {
      
          It "Should return a valid map" {
              $map | should Not BeNullOrEmpty
          }
          It "Global settings should be inherited as properties" {
              $map.abc.port | should Not BeNullOrEmpty
              $map.abc.port | should be $map.settings.port
          }
        
      }
      
      Context "when map contains generic keys" {
        $p = get-entry machine13 $map
        It "Should retrieve a valid profile" {
            $p | Should Not BeNullOrEmpty
            # should _fullpath be replaced or not?
            $p._fullpath | Should Be "machine_N_"           
        }
        It "Should replace variable placeholders" {
            $p.computername | Should Be "machine13.cloudapp.net"
            $p.Port | Should Be 13985
        }
      }
}