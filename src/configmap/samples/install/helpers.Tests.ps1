BeforeAll {
    . "$PSScriptRoot/helpers.ps1"
}

Describe "parse-packageEntry" {
    
    It "should parse package entries" {
        $entry = "foo"
        $package = parse-packageEntry $entry
        $package.name | Should -Be "foo"
        $package.installer | Should -Be "choco"
        $package.installerArgs | Should -Be "install", "-y", "foo"
    }
    It "should parse package entries with installer" {
        $entry = "foo [choco install -y foo]"
        $package = parse-packageEntry $entry
        $package.name | Should -Be "foo"
        $package.installer | Should -Be "choco"
        $package.installerArgs | Should -Be "install", "-y", "foo"
    }
    It "should parse package entries with installer and args" {
        $entry = "foo [choco install -y foo -pre]"
        $package = parse-packageEntry $entry
        $package.name | Should -Be "foo"
        $package.installer | Should -Be "choco"
        $package.installerArgs | Should -Be "install", "-y", "foo", "-pre"
    }
    It "should parse package entries with installer and args only" {
        $entry = "foo [--pre]"
        $package = parse-packageEntry $entry
        $package.name | Should -Be "foo"
        $package.installer | Should -Be "choco"
        $package.installerArgs | Should -Be "install","-y","foo","--pre"
    }
    
}