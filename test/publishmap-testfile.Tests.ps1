
Describe "parse publish map" {
  $map = import-publishmap -maps "$PSScriptRoot\input\publishmap.test.config.ps1"  

  Context "When map is parsed" {
      It "Should return a map" {
        $map | Should Not BeNullOrEmpty     
      }
      It "A global pmap is created" {
        $global:pmap | Should Not BeNullOrEmpty
        $global:pamp
      }
      It "Profiles should be exposed at project level" {
        $p = $map.test.override_default_profiles.dev 
        $p | Should Not BeNullOrEmpty        
        $map.test.override_default_profiles.dev | Should Be $map.test.override_default_profiles.profiles.dev
      }
      It "projects should be exposed at profile level" {
        $map.test.override_default_profiles.dev.project | Should Not BeNullOrEmpty        
        $map.test.override_default_profiles.dev.project | Should Be $map.test.override_default_profiles
      }
      It "profiles should have fullpath property" {
            $p = $map.test.override_default_profiles.dev         
          $p.fullpath | Should Be "test.override_default_profiles.dev"
      }
      
  }
  Context "When global_profiles are defined" {      
      It "global profiles should be inherited" {
          $t = $map.test
          $t | Should Not BeNullOrEmpty
          $t.db_1.profiles | Should Not BeNullOrEmpty

          $t.db_1.profiles.Count | Should Be $t.global_profiles.Count
      }
      
      It "should respect local profile properties " {
        $p = $map.test.override_default_profiles
        $p.profiles.dev.password | Should Be "overriden"
        $p.profiles.dev.new_prop | Should Be "abc"
    }
    
     It "profiles should be merged" {
        $p = $map.test.additional
        $p.profiles.prod | Should Not BeNullOrEmpty
        $p.profiles.Count | Should Be 3         
     }
     It "merged profiles should be exposed at project level" {
        $p = $map.test.additional
        $p.prod | Should Not BeNullOrEmpty         
        $p.dev | Should Not BeNullOrEmpty         
        $p.qa | Should Not BeNullOrEmpty         
     }
  }
  
  
  Context "When project has inherit=false" {
      $p = $map.test.do_not_inherit_global
      <#It "global profiles should NOT be inherited" {
           $p.profiles.Count | Should Be 1
           $p.profiles.dev | Should Not Be $null
            
      } #> 
      <# 
      It "global profile properties should NOT be inherited" {
          $p.profiles.dev.new_prop | Should Be "abc"    
          $p.profiles.dev.Password | Should BeNullOrEmpty
          # or should it?
          #$p.profiles.dev.Password | Should Be "?"   
      } #>
  }
  
  Context "When top level settings are defined" {
    $msg =  "should settings be inherited as wrapped 'settings' object or as properties? for now, they are inherited as properties due to global_profiles hack"      
     It "settings should be inherited in projects" {
         $p = $map.test.db_1
     #    $p.settings.siteAuth | Should Not BeNullOrEmpty
     #    $p.settings.siteAuth.username | Should Be "user"
        Set-TestInconclusive -Message $msg
     }
     It "settings should be inherited in profiles" {
         $p = $map.test.db_1.dev
         #$p.settings.siteAuth | Should Not BeNullOrEmpty
         #$p.settings.siteAuth.username | Should Be "user"
        Set-TestInconclusive -Message $msg
     }
    
  }
}

# this will search for all pester scripts
#Invoke-Pester -Script .

Describe "Get publishmap entry" {
    $map = import-publishmap -maps "$PSScriptRoot\input\publishmap.test.config.ps1"    
    Context "When get-profile is called" {
        It "proper profile is retireved" {
            $p = get-profile test.use_default_profiles.dev -map $map
            $p | Should Not BeNullOrEmpty
            $p.Profile | Should Not BeNullOrEmpty
            $p.Profile | Should Be $map.test.use_default_profiles.dev
        }
    }
    
    Context "When generic profile exists" {
        $p = get-profile test.generic.prod3 -map $map
        It "Should retrieve a valid profile" {
            $p | Should Not BeNullOrEmpty
            $p.profile.fullpath | Should Not BeNullOrEmpty
            $p.profile.fullpath | Should Be "test.generic.prod3"           
        }
        It "Should replace variable placeholders" {
            $p.profile.computername | Should Be "prod3.cloudapp.net"
            $p.profile.Port | Should Be 1380
        }
    }
}