BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    import-module $PSScriptRoot\..\..\configmap.psm1
}

Describe "install" {
    BeforeAll {
        $modules = . "$PSScriptRoot/.configuration.map.ps1"
        Mock install-mypackage {
            param($package)
            write-host "mocked package install of $($package.name)"
        }
    }

    It "can list keys" {
        $list = Get-CompletionList $modules
        $list | Should -not -BeNullOrEmpty
        $list.Keys | Should -Contain "media*"
    }

    It "can install single package" {
        $list = Get-CompletionList $modules
        $target = $list["telnet"]
        
        Invoke-ModuleCommand $target "telnet"
        Should -Invoke install-mypackage
    }

    It "can install group" {
        $list = Get-CompletionList $modules
        $target = $list["core"]
        
        Invoke-ModuleCommand $target "core"
    }
}