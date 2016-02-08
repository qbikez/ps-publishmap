. "$PSScriptRoot\includes.ps1"



Describe "parse publish map" {
  $maps = @(gci "$PSScriptRoot\input" -filter "publishmap.*.config.ps1" | % { 
   @{ file=$_.name; item = $_ }
  })

  Context "When map is parsed" {
      It "Should return a valid map for '<file>'" -TestCases $maps {
        param([string]$file, $item)
        $map = import-publishmap $item
        $map | Should Not BeNullOrEmpty     
      }
  }
}