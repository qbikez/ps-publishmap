$pester = "$psscriptroot\..\paket-files\pester\pester\pester.psm1"

import-module $pester 




Describe "parse publish map" {
  Context "When map is parsed" {

      & "$PSScriptRoot\..\publishmap\publishmap.config.ps1" -maps "$PSScriptRoot\publishmap.test.config.ps1"    

      It "A global pmap is created" {
        $global:pmap | Should Not BeNullOrEmpty
        $global:pamp
      }

      It "global properties are inherited" {
      }
    }
}

Invoke-Pester