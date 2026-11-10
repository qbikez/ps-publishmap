BeforeAll {
    . $PSScriptRoot/includes.ps1 -internal
}


Describe "internal: adding properties" {
    Context "when adding hashtable to existing hashtable" {
        BeforeAll {
            $toadd = @{ 
                profiles = @{ 
                    dev = @{ title = "dev" }
                    qa  = @{ title = "qa" }
                }
            }
            $existing = @{
                profiles = @{
                    prod = @{ name = "prod" }
                }
            } 

            $added = $existing | add-properties -props $toadd -merge
        }

        It "should merge hashtables" {
            $added.profiles.dev | Should -Not -BeNullOrEmpty
            $added.profiles.qa | Should -Not -BeNullOrEmpty
            $added.profiles.prod | Should -Not -BeNullOrEmpty
                
        }
    }
}
