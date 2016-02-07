. "$PSScriptRoot\includes.ps1"


  Describe "adding properties" {
        Context "when adding hashtable to existing hashtable" {
            $toadd = @{ 
                profiles = @{ 
                    dev = @{ title = "dev" }
                    qa = @{ title = "qa" }
                }
            }
            $existing = @{
                profiles = @{
                    prod = @{ name = "prod" }
                }
            } 

            $added = $existing | add-properties -props $toadd -merge

            It "should merge hashtables" {
                $added.profiles.dev | should not benullorempty
                $added.profiles.qa | should not benullorempty
                $added.profiles.prod | should not benullorempty
            }
        }
  }


Describe "parse simple map" {
      $m = @{
        settings = @{
            Port = 22
            _strip = $true
        }
        machine_N_ = @{ computername = "machine{N}.cloudapp.net"; Port = "{N}985" }
        abc = @{ ComputerName = "pegaz.legimi.com"; }    
      }
      $map = import-mapobject $m 
      
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


Describe "parse multilevel map" {
      Context "map with one level nesting" {
        
            $m = @{
            test = @{
                settings = @{
                    Port = 22
                    _strip = $true
                }
                machine_N_ = @{ computername = "machine{N}.cloudapp.net"; Port = "{N}985" }
                abc = @{ ComputerName = "pegaz.legimi.com"; }    
            }
          }

          $map = import-mapobject $m 

          It "Global settings should be inherited as properties in subgroup" {
              $map.test.abc.port | should Not BeNullOrEmpty
              $map.test.abc.port | should be $map.test.settings.port
          }
      }
      Context "map with one level nesting" {
      
            $m = @{
                test = @{
                    settings = @{
                        Port = 22
                        _strip = $true
                        profiles = @{
                            dev = @{
                                port = "dev"
                            }
                        }
                    }                                
                   project1 = @{
                        sln = "abc.sln"
                        profiles = @{
                            prod = @{
                                port = "prod"
                            }
                        }
                   }
                }
            }

          $map = import-mapobject $m 


          It "local profiles should be retained" {
              $map.test.project1 | should Not BeNullOrEmpty
              $map.test.project1.profiles | should Not Benullorempty
              $map.test.project1.profiles.prod | should Not Benullorempty
              $map.test.project1.profiles.prod.port | should be "prod"
          }

          It "global profiles should be inherited" {
              $map.test.project1 | should Not BeNullOrEmpty
              $map.test.project1.profiles | should Not Benullorempty
              $map.test.project1.profiles.dev | should Not Benullorempty
              $map.test.project1.profiles.dev.port | should be "dev"
          }
    }
  }
