Describe "canary" {
    It "fails on purpose" { $true | Should -BeFalse }
}
