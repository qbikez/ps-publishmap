. "$PSScriptRoot\includes.ps1"


Describe "parse map with variables" { 
      $m = @{
                name = "some-name.com"
                base_url = "https://{name}"
                services = @{
                    svc1 = @{
                        url = "https://{name}/svc1"
                        url_staging = "https://{name}/svc1{?postfix}"
                    }
                    svc2 = @{
                        url = "{base_url}/svc2"
                        help = "{url}/help"
                    }
                    svc3 = @{
                        name = "svc3"
                        url = "https://some-name.com/{name}"
                        help = "{url}/help"
                    }
                    svc4 = @{
                        name = "svc4"
                        # this is tricky: {base_url} references {name}, which is overriden in svc4
                        # the result will be "https://svc4/svc4". sorry, Winnetou
                        url = "{base_url}/{name}"
                        help = "{url}/help"
                        something = "{help}/something"
                        other = "{services.svc1.url}"
                    }
                }
            }

          $map = import-map $m 

     Context "when map is imported" {
      
          It "Should return a valid map" {
              $map | should Not BeNullOrEmpty
          }
          It "variables should not be substituted" {
              $map.base_url | should Be  "https://{name}"
          }
      }

      Context "when entry is retrieved" {
          It "variables should be substituted" {
            $url = $map | get-entry "base_url" 
            $url | should be "https://some-name.com"
          }
         
          It "variables should be substituted in nested objects" {
            $url = $map | get-entry "services.svc1.url" 
            $url | Should Be "https://some-name.com/svc1"            
          }
           It "optional variables should be removed if missing" {
            $url = $map | get-entry "services.svc1.url_staging" 
            $url | should be "https://some-name.com/svc1"
          }
          It "one-level chained variables should be substituted " {
            $url = $map | get-entry "services.svc2.url" 
            $url | Should Be "https://some-name.com/svc2"            
          }
          It "two-level chained variables should be substituted " {
            $url = $map | get-entry "services.svc2.help" 
            $url | Should Be "https://some-name.com/svc2/help"            
          }
          It "nested object variables should override parent" {
            $url = $map | get-entry "services.svc3.url" 
            $url | Should Be "https://some-name.com/svc3"            
          }
          It "variable override should affect parent variables" {
            $url = $map | get-entry "services.svc4.base_url" 
            $url | Should Be "https://svc4"            
          }
          It "multi-level chained variables with override should be substituted" {
            $url = $map | get-entry "services.svc4.help" 
            $url | Should Be "https://svc4/svc4/help"            
          }

          It "variables referencing other objects should be replaced" {
            $url = $map | get-entry "services.svc4.other" 
            $url | Should Be  "https://some-name.com/svc1"         
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
      $map = import-map $m 
      
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

          $map = import-map $m 

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

          $map = import-map $m 

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


