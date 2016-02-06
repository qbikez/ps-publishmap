$pesterPath = "$psscriptroot\..\paket-files\pester\pester\pester.psm1"
$publishmapPath = "$psscriptroot\..\src\publishmap\publishmap.psm1"
import-module $pesterPath 
if ((get-module PublishMap) -ne $null) {
    write-host "reloading PublishMap module"
    remove-module PublishMap
}
import-module $publishmapPath

Describe "parse publish map" {
      $map = import-mapfile -maps "$PSScriptRoot\publishmap.test.config.ps1"    

  Context "When map is parsed" {
      It "Should return a map" {
        $map | Should Not BeNullOrEmpty     
      }
      It "A global pmap is created" {
        $global:pmap | Should Not BeNullOrEmpty
        $global:pamp
      }
      It "Profiles should be exposed at project level" {
        $p = $map.test.override_default_profiles.dev | Should Not BeNullOrEmpty        
        $map.test.override_default_profiles.dev | Should Be $map.test.override_default_profiles.profiles.dev
      }
      
  }
  Context "When global_profiles are defined" {      
      It "global profiles should be inherited" {
          $t = $map.test
          $t | Should Not BeNullOrEmpty
          $t.db_legimi.profiles | Should Not BeNullOrEmpty
          $t.db_legimi.profiles.Count | Should Be $t.global_profiles.Count
      }
      
      It "should respect local profile properties " {
        $p = $map.test.override_default_profiles
        $p.profiles.dev.password | Should Be "overriden"
        $p.profiles.dev.new_prop | Should Be "abc"
    }
  }
  
  Context "When project has $inherit=false" {
      $p = $map.test.do_not_inherit_global
      It "global profiles should NOT be inherited" {
           $p.profiles.Count | Should Be 1
           $p.profiles.dev | Should Not Be $null
            
      }  

      It "global profile properties should NOT be inherited" {
          $p.profiles.dev.new_prop | Should Be "abc"    
          $p.profiles.dev.Password | Should BeNullOrEmpty
          # or should it?
          #$p.profiles.dev.Password | Should Be "?"   
      }
  }
  
  Context "When top level settings are defined" {      
     It "settings should be inherited in projects" {
         $p = $map.test.db_legimi
         $p.settings.siteAuth | Should Not BeNullOrEmpty
         $p.settings.siteAuth.username | Should Be "user"
     }
     It "settings should be inherited in profiles" {
         $p = $map.test.db_legimi.dev
         $p.settings.siteAuth | Should Not BeNullOrEmpty
         $p.settings.siteAuth.username | Should Be "user"
     }
  }
}

# this will search for all pester scripts
#Invoke-Pester -Script .