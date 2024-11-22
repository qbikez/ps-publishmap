[CmdletBinding()]
param(
    [ArgumentCompleter({
            param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            # ipmo configmap
            return Get-ModuleCompletion "./.build.map.ps1" @PSBoundParameters
        })] 
    $module = $null
)
DynamicParam {
    # ipmo configmap
    return Get-ModuleDynamicParam "./.build.map.ps1" $module $PSBoundParameters
}

process {
    # ipmo configmap
    Invoke-Module "./.build.map.ps1" $PSBoundParameters
}
