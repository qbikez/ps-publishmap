$helpersPath = (Split-Path -Parent $MyInvocation.MyCommand.Definition)

. "$helpersPath\src\configmap.ps1"

Export-ModuleMember `
    -Function `
    Resolve-ConfigMap, Assert-ConfigMap, Test-IsParentEntry, Test-IsHierarchicalKey, Split-HierarchicalKey, Resolve-HierarchicalPath, `
    Get-CompletionList, Get-ValuesList, Get-ScriptArgs, Get-MapEntries, Get-MapEntry, Get-EntryCommand, `
    Invoke-EntryCommand, Invoke-Set, Invoke-Get, Get-EntryCompletion, Get-EntryDynamicParam, `
    Invoke-Entry, Invoke-QBuild, Invoke-QConf, ConvertTo-MapResult, `
    Initialize-ConfigMap, Initialize-BuildMap, Get-MapLanguage, Merge-IncludeDirectives `
    -Alias *
    