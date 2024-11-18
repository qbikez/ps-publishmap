BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    import-module $PSScriptRoot\..\..\configmap.psm1
    $modules = . "$PSScriptRoot/.configuration.map.ps1"
}

Describe "install" {
    It "can list keys" {
        $list = Get-CompletionList $modules
        $list | Should -not -BeNullOrEmpty
        $list.Keys | Should -Contain "media*"
    }
}