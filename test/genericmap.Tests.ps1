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
        abc = @{ ComputerName = "pegaz.legimi.com";  }    
      }
      $map = import-mapobject $m -verbose
      
      Context "when map is imported" {
      
          It "Should return a valid map" {
              $map | should Not BeNullOrEmpty
              $map.gettype().fullname | should be "System.Collections.Hashtable"
          }
          It "Global settings should be inherited as properties" {
              $map.abc.port | should Not BeNullOrEmpty
              $map.abc.port | should be $map.settings.port
          }
          It "_fullpath should be set" {
            $map.abc._fullpath | should be "abc"
          }
      }
      
      Context "when map contains generic keys" {
        $p = get-entry machine13 $map
        It "Should retrieve a valid profile" {
            $p | Should Not BeNullOrEmpty
            $p._fullpath | Should Be "machine13"           
        }
        It "Should replace variable placeholders" {
            $p.computername | Should Be "machine13.cloudapp.net"
            $p.Port | Should Be 13985
        }
      }
}


Describe "parse map with one level nesting" {      
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

     Context "when map is imported" {
      
          It "Should return a valid map" {
              $map | should Not BeNullOrEmpty
          }
          It "Global settings should be inherited as properties" {
              $map.test.abc.port | should Not BeNullOrEmpty
              $map.test.abc.port | should be $map.test.settings.port
          }
          It "_fullpath should be set" {
            $map.test.abc._fullpath | should be "test.abc"
          }
      }
      
      Context "when there are global settings" {
        
          It "Global settings should be inherited as properties in subgroup" {
              $map.test.abc.port | should Not BeNullOrEmpty
              $map.test.abc.port | should be $map.test.settings.port
          }
      }
}

Describe "parse map with two level nesting" { 
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
                            str = "abc"
                            prod = @{
                                port = "prod"
                            }
                        }
                   }
                   project2 = @{
                        sln = "abc.sln"
                        profiles = @{
                            str = "abc"
                            prod = @{
                                port = "prod"
                            }
                        }
                   }
                }
            }

          $map = import-mapobject $m 

     Context "when map is imported" {
      
          It "Should return a valid map" {
              $map | should Not BeNullOrEmpty
          }
          It "_fullpath should be set on local dictionaries" {
            $map.test.project1._fullpath | should be "test.project1"
            $map.test.project1.profiles.prod._fullpath | should be "test.project1.profiles.prod"
          }
          It "_fullpath should be set on inherited dictionaries" {
            $map.test.project1.profiles.dev._fullpath | should be "test.project1.profiles.dev"
            $map.test.project2.profiles.dev._fullpath | should be "test.project2.profiles.dev"
        }
      }

      Context "when there are global settings" {
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
    
    Context "when there is local inheritance" {
        It "children should inherit from parents" {
            $map.test.project1.profiles.prod.str | should Not BeNullOrEmpty
            $map.test.project1.profiles.prod.str | should Be $map.test.project1.profiles.str 
        }
        It "children should inherit from grandparents" {
            $map.test.project1.profiles.prod.sln | should Not BeNullOrEmpty
            $map.test.project1.profiles.prod.sln | should Be $map.test.project1.sln         
        }
    }
  }
