. $PSScriptRoot\includes.ps1

import-module Pester
#import-module PublishMap

Describe "parse map object" {
  
  
     Context "when map references properties" {
      $m = @{
          test1 = @{
              settings = @{
                abc = "inherited"               
              }
              global_profiles = @{
                      parent_property = "this_is_from_parent"
                      prod_XX_ = @{
                          name = "prod{XX}"
                      }
                      prod = @{  
                          what = "something"
                          test = "v{what}v"   
                          from_parent = "v{parent_property}v"               
                      }
                  }
              default_with_stub = @{             
                  profiles = @{
                      prod_XX_ = @{
                          url2 = "http://test:{XX}443/something"
                          url1 = "http://test:{vars.XX}443/something"                                                    
                      }
                  }                       
              }
              override_parent_with_stub = @{
                  parent_property = "overriden"         
                  profiles = @{
                  }          
              }
              default = @{     
              }
              override = @{
                  parent_property = "overriden"         
              }
              
            }
        }
        
        $map = import-publishmap $m
        It "Should replace generic profile" {
            $e = get-entry "prod13" $map.test1.default_with_stub
            $e.name | Should Be "prod13"
            $e.url1 | Should Be "http://test:13443/something"
            $e.url2 | Should Be "http://test:13443/something"
        }
        
        It "Should get standard properties  with stubs" {
            $e = get-entry "prod" $map.test1.default_with_stub
            $e | Should Not BeNullOrEmpty
            $e.what | Should Be "something"
        }
        
        It "Should replace property variables with stubs" {
            $e = get-entry "prod" $map.test1.default_with_stub
            $e | Should Not BeNullOrEmpty
            $e.test | Should Be "v$($e.what)v"
            #$e.from_parent | Should Be "v$($map.test1.global_profiles.parent_property)v"
            $e.from_parent | Should Be "vthis_is_from_parentv"
        }
        
         It "Should replace overriden property variables with stubs" {
            $e = get-entry "prod" $map.test1.override_parent_with_stub
            $e | Should Not BeNullOrEmpty
            $e.test | Should Be "v$($e.what)v"
            #$e.from_parent | Should Be "v$($map.test1.global_profiles.parent_property)v"
            $e.from_parent | Should Be "voverridenv"
        }
        
           It "Should get standard properties without stubs" {
            $e = get-entry "prod" $map.test1.default
            $e | Should Not BeNullOrEmpty
            $e.what | Should Be "something"
        }
        
        It "Should replace property variables without stubs" {
            $e = get-entry "prod" $map.test1.default
            $e | Should Not BeNullOrEmpty
            $e.test | Should Be "v$($e.what)v"
            #$e.from_parent | Should Be "v$($map.test1.global_profiles.parent_property)v"
            $e.from_parent | Should Be "vthis_is_from_parentv"
        }
        
         It "Should replace overriden property variables without stubs" {
            $e = get-entry "prod" $map.test1.override_parent
            $e | Should Not BeNullOrEmpty
            $e.test | Should Be "v$($e.what)v"
            #$e.from_parent | Should Be "v$($map.test1.global_profiles.parent_property)v"
            $e.from_parent | Should Be "voverridenv"
        }
        
    }
  
  Context "when map references variables only" {
      $m = @{
          test = @{
              settings = @{
                abc = "inherited"               
              }
              global_profiles = @{
                      parent_property = "parent_property"
                      prod_XX_ = @{  
                          what = "what-prod{XX}"
                      }
                  }
              default_with_stub = @{    
                   profiles = @{
                      prod_XX_ = @{
                          
                      }
                  }                                
              }
              override_parent_with_stub = @{
                  parent_property = "overriden"
                  profiles = @{
                      prod_XX_ = @{
                          
                      }
                  }
              }
               default = @{    
              }
              override_parent = @{
                  parent_property = "overriden"
              }
              
            }
        }

        $map = import-publishmap $m
        
        It "Should Replace property variables with stub" {
            $e = get-entry "prod13" $map.test.default_with_stub
            $e | Should Not BeNullOrEmpty
            $e.what | Should Be "what-prod13"
            $e.parent_property | Should Be "parent_property"
        }
        It "Should override parent variables with stub" {
            $e = get-entry "prod13" $map.test.override_parent_with_stub
            $e | Should Not BeNullOrEmpty
            $e.what | Should Be "what-prod13"
            $e.parent_property | Should Be "overriden"
        }
        It "Should Replace property variables without stub" {
            $e = get-entry "prod13" $map.test.default
            $e | Should Not BeNullOrEmpty
            $e.what | Should Be "what-prod13"
            $e.parent_property | Should Be "parent_property"
        }
        It "Should override parent variables without stub" {
            $e = get-entry "prod13" $map.test.override_parent
            $e | Should Not BeNullOrEmpty
            $e.what | Should Be "what-prod13"
            $e.parent_property | Should Be "overriden"
        }
    }
  
  
    
  
}