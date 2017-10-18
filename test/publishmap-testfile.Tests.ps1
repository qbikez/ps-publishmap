. $PSScriptRoot\includes.ps1


function Compare-Dicts($src, $dst, $exclude = @(), [int]$level = 0) {
    if ($level -gt 10) {
        throw "recursion to deep"
    }
    foreach($kvp in $src.GetEnumerator()) {
        try {
            if ($kvp.key -in $exclude) { continue }
            # dictionaries and arrays will be cloned!
            if ($kvp.value -is [Hashtable] -or $kvp.value -is [System.Collections.Specialized.OrderedDictionary]){
                compare-dicts $kvp.value $dst[$kvp.key] -exclude:$exclude -level ($level+1)
            } else {
                $kvp.Value | Should Be $dst[$kvp.Key]
            }
        } catch {
            throw "property '$($kvp.key)' mismatch!`r`n$($_.Exception.Message)"
        }
    }
}

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
        $basicprofiles = @()
        foreach($_ in $p.profiles.GetEnumerator()) {
            if ($_.key -notmatch "_staging" -and $_.key -notmatch "swap_") {
                $basicprofiles += $_
            }
        }  
        $basicprofiles.Count | Should Be 5      
     }
     It "merged profiles should be exposed at project level" {
        $p = $map.test.additional
        $p.prod | Should Not BeNullOrEmpty         
        $p.dev | Should Not BeNullOrEmpty         
        $p.qa | Should Not BeNullOrEmpty         
     }
  }
  
  <#
  Context "When project has inherit=false" {
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
  #>
  
  Context "When _nherit_from is defined and local profile is defined" {      
      It "Should inherit propeties from global profile" {
          $profile = $map.test.override_default_profiles.dev_copy
          $profile.connectionStringName | Should Not BeNullOrEmpty
          $profile.connectionStringName | Should Be $map.test.override_default_profiles.dev.connectionStringName          
      }
      It "Should override from local profile" {
          $profile = $map.test.override_default_profiles.dev_copy
          $profile.Config | Should Not BeNullOrEmpty
          $profile.Config | Should Be "copy"          
      }
      It "Should override from local inherited profile" {
          $profile = $map.test.override_default_profiles.dev_copy
          $profile.password | Should Not BeNullOrEmpty
          $profile.password | Should Be $map.test.override_default_profiles.dev.password
      }
      It "Should inherit overriden project properties" {
          $profile = $map.test.override_default_profiles.dev_3
          $profile.appname | Should Not BeNullOrEmpty
          $profile.appname | Should Be $map.test.override_default_profiles.dev.appname
      }
       It "Should override in child profile" {
          $profile = $map.test.override_default_profiles.dev_3
          $profile.Config | Should Not BeNullOrEmpty
          $profile.profile | Should Be  "ne-dev-3.pubxml"
          $profile.Task | Should Be  "Migrate-3"
          
      }
  }

  Context "When _nherit_from is defined and NO local profile" {      
      It "Should inherit propeties from global profile" {
          $profile = $map.test.additional.dev_2
          $profile.connectionStringName | Should Not BeNullOrEmpty
          $profile.connectionStringName | Should Be $map.test.additional.dev.connectionStringName          
      }     
      It "Should override from local inherited profile" {
          $profile = $map.test.additional.dev_2
          $profile.password | Should Not BeNullOrEmpty
          $profile.password | Should Be $map.test.additional.dev.password         
      }
  }

  Context "When top level settings are defined" {
    $msg =  "should settings be inherited as wrapped 'settings' object or as properties? for now, they are inherited as properties due to global_profiles hack"      
     It "settings should be inherited in projects" {
         $p = $map.test.db_1
         $p.siteAuth | Should Not BeNullOrEmpty
         $p.siteAuth.username | Should Be "user"
        # Set-TestInconclusive -Message $msg
     }
     It "settings should not be inherited in profiles" {
         $p = $map.test.db_1.dev
         $p.siteAuth | Should BeNullOrEmpty
         $p.siteAuth.username | Should BeNullOrEmpty
        #Set-TestInconclusive -Message $msg
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
            # this will be a clone!
            $p.Profile | Should Not Be $map.test.use_default_profiles.dev
       
            $p.Profile.Keys.Count | Should BeGreaterThan $map.test.use_default_profiles.dev.Keys.Count
            compare-dicts $p.Profile $map.test.use_default_profiles.dev -exclude "_vars","_clone_meta","project"
           
            $p.Profile["_vars"] | Should Not Be $null

            # should _vars contain anything??
            #$p.Profile["_vars"] | Should Not BeNullOrEmpty
            #Set-TestInconclusive 
            <# the profile will be cloned, should check for object equality
            $p.Profile | Should Be $map.test.use_default_profiles.dev
            #>
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
