$helpersPath = (Split-Path -parent $MyInvocation.MyCommand.Definition);

. "$helpersPath\configmap.ps1"

Export-ModuleMember `
    -Function `
        Get-CompletionList, Get-ValuesList, `
        Get-MapModules, Get-MapModule, Get-ModuleCommand, `
        Get-ScriptArgs, Invoke-ModuleCommand, Invoke-Set, Invoke-Get,`
        Get-ModuleCompletion, `
        qbuild, qconf, qrun `
    -Alias *
    