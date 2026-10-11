$helpersPath = (Split-Path -Parent $MyInvocation.MyCommand.Definition)

. "$helpersPath\src\configmap.ps1"

Export-ModuleMember `
    -Function `
    Import-ConfigMap, Resolve-ConfigMap, Assert-ConfigMap, Test-IsParentEntry, `
    Get-CompletionList, Get-ScriptArgs, Get-MapEntries, Get-MapEntry, Get-EntryCommand, `
    Invoke-EntryCommand, Invoke-Set, Invoke-Get, Get-EntryCompletion, Get-EntryDynamicParam, `
    Get-ConfigMapCommandCatalog, Initialize-QBuildAgent, `
    Invoke-QBuild, Invoke-QConf, Invoke-QRun, ConvertTo-MapResult, `
    Initialize-ConfigMap, Initialize-BuildMap, Initialize-ProcessMap, Get-MapLanguage, Merge-IncludeDirectives, Add-BaseDir `
    -Alias qbuild, qconf, qrun `
    -Variable ImportConfigMap
    