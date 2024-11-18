$helpersPath = (Split-Path -parent $MyInvocation.MyCommand.Definition);

. "$helpersPath\configmap.ps1"

Export-ModuleMember `
    -Function `
        Get-CompletionList, Get-ValuesList, Invoke-ModuleCommand `
    -Alias *
