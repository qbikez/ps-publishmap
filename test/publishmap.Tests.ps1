. $PSScriptRoot\includes.ps1

Describe "parse map object" {

  Context "when map looks like this" {
      $m = @{
          test = @{
              settings = @{
                abc = "inherited"               
              }
              global_profiles = @{
                      global_property ="im sooo global"
                      dev = @{  what = "dev"                    
                      }
                      qa = @{   what = "qa"                   
                      }
                  }
              default = @{
                  project_property = "project_level"
                  profiles = @{
                  }                 
              }
              default_no_stubs = @{
                  project_property = "project_level"
              }
              additional = @{
                  project_property = "project_level"
                  profiles = @{
                      prod = @{  
                        what = "prod"                        
                      }
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
     
     It "project properties should be inherited in manual profiles" {
          $p = $map.test.additional
        $p.profiles.prod.project_property | Should be $p.project_property
     }
     It "project properties should be inherited in profiles from global" {
        $p = $map.test.additional
        $p.profiles.dev.project_property | Should be $p.project_property                 
        $p = $map.test.default
        $p.profiles.qa.project_property | Should be $p.project_property
        $p.profiles.dev.project_property | Should be $p.project_property
     }

     It "global properties should be inherited in profiles" {
        $p = $map.test.additional
        $p.profiles.dev.global_property | Should Not BeNullOrEmpty
        $p.profiles.prod.global_property | Should Not BeNullOrEmpty
     }
     It "global properties should be inherited in profiles from global" {
        $p = $map.test.default
        $p.profiles.dev.global_property | Should Not BeNullOrEmpty
     }
     It "global properties should be inherited in profiles from global without stubs" {
        $p = $map.test.default_no_stubs
        Set-TestInconclusive "this is a feature request"
            <#        
        $p.profiles.dev.global_property | Should Not BeNullOrEmpty
        #>
     }
     
     <# this is not really required:
     It "global properties should be inherited in projects" {
        $p = $map.test.additional        
        $p.global_property | Should Not BeNullOrEmpty
     }
     #>
     
  }
}


Describe "parse multiple map objects" {
      $m1 = @{
          test1 = @{
          }
      }   
      $m2 = @{
          test2 = @{
          }
      }
      
      Context "when maps are imported" {
          $map1 = import-publishmap $m1
          $map2 = import-publishmap $m2
          
          It "they can be merged" {
              $merged = $map1 + $map2
          } 
      }
}