. $PSScriptRoot\includes.ps1

Describe "parse map object" {

  Context "when map looks like this" {
      $m = @{
          test = @{
              settings = @{
                abc = "inherited"               
              }
              global_profiles = @{
                      dev = @{  what = "dev"                    
                      }
                      qa = @{   what = "qa"                   
                      }
                  }
              additional = @{
                  profiles = @{
                      prod = @{  what = "prod"                        
                      }
                  }
              }
              default = @{
                  profiles = @{
                      }
                  }
              }
          }
      
      
      $map = import-publishmap $m 
      It "profiles should be merged" {
        $p = $map.test.additional
        $p.profiles.prod | Should Not BeNullOrEmpty  
        $p.profiles.prod.what | Should be "prod"    
        $p.profiles.dev | Should Not BeNullOrEmpty         
        $p.profiles.dev.what | Should be "dev"
        $p.profiles.qa | Should Not BeNullOrEmpty         
        
      }
      It "merged profiles should be exposed at project level" {
        $p = $map.test.additional
        $p.prod | Should Not BeNullOrEmpty         
        $p.dev | Should Not BeNullOrEmpty         
        $p.qa | Should Not BeNullOrEmpty         
     }
     It "fullpath should be set" {
        $p = $map.test.additional
        $p.prod.fullpath | Should Be "test.additional.prod"
        $p.dev.fullpath | Should Be "test.additional.dev"
        $p = $map.test.default
        $p.dev.fullpath | Should Be "test.default.dev"
        $p.qa.fullpath | Should Be "test.default.qa"
     }
     
  }
}
