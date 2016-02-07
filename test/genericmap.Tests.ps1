. "$PSScriptRoot\includes.ps1"

Describe "parse generic map" {
      $m = @{
        settings = @{
            Port = 22
            strip = $true
        }
        machine_N_ = @{ computername = "machine{N}.cloudapp.net"; Port = "{N}985" }
        abc = @{ ComputerName = "pegaz.legimi.com"; }    
      }
      $map = import-mapobject $m
      
      Context "when generic map is imported" {
      
          It "Should return a valid map" {
              $map | should Not BeNullOrEmpty
          }
          It "Global settings should be inherited as properties" {
              $map.abc.port | should Not BeNullOrEmpty
              $map.abc.por | should be $map.settings.port
          }
        
      }
}