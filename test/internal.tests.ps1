. $PSScriptRoot\includes.ps1 -internal


  Describe "internal: adding properties" {
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
