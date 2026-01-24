BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\..\configmap.psm1
}


Describe "install" -Skip {
    BeforeAll {
        $modules = . "$PSScriptRoot/.configuration.map.ps1"
        Mock install-mypackage {
            param($package)
            Write-Host "mocked package install of $($package.name)"
        }
    }

    It "can list keys" {
        $list = Get-CompletionList $modules
        $list | Should -Not -BeNullOrEmpty
        $list.Keys | Should -Contain "media*"
    }

    It "can install single package" {
        $list = Get-CompletionList $modules
        $target = $list["telnet"]
        
        Invoke-EntryCommand $target "exec"
        Should -Invoke install-mypackage
    }

    It "can install group" {
        $list = Get-CompletionList $modules
        $target = $list["core*"]
        
        Invoke-EntryCommand $target "exec"
    }
}