#requires -modules ConfigMap

[CmdletBinding()]
param(
    [ArgumentCompleter({
            param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $modules = . "$PSScriptRoot/.configuration.map.ps1"

            $list = Get-CompletionList $modules
            return $list.Keys | ? { $_.startswith($wordToComplete) }
        })] 
    $module = $null
)


$modules = . "$PSScriptRoot/.configuration.map.ps1"
$list = Get-CompletionList $modules

write-verbose "installing targets: $target" -verbose
@($module) | % {
    if ($_ -is [ScriptBlock]) {
        & $_
        return
    }
    $target = $list[$module]
    if (!$target) {
        Write-Warning "No module '$module' found."
        continue
    }

    if ($null -eq $target.list) {
        write-verbose "installing '$($target.name)'" -verbose
        install-mypackage $target
    }
    else {
        write-verbose "installing group '$module'" -verbose
        install-mygroup $target
    }
}