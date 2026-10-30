[CmdletBinding()]
param(
    [ArgumentCompleter({
            param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            # ipmo configmap
            return Get-ModuleCompletion "./.configuration.map.ps1" @PSBoundParameters
        })] 
    $module = $null
)
DynamicParam {
    # ipmo configmap
    return Get-ModuleDynamicParam "./.configuration.map.ps1" $module $PSBoundParameters
}

process {
    # ipmo configmap
    Invoke-Module "./.configuration.map.ps1" $module $PSBoundParameters
}
