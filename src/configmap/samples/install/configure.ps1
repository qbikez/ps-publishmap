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

$targets = $list.GetEnumerator() | ? { $_.key -in @($module) }
write-verbose "installing targets: $($targets.Keys)" -verbose

@($targets) | % {
    write-host "installing module '$($_.key)'"

    Invoke-ModuleCommand -module $_.value -key $_.Key
    # if ($_ -is [ScriptBlock]) {
    #     & $_
    #     return
    # }
    # $target = $list[$module]
    # if (!$target) {
    #     Write-Warning "No module '$module' found."
    #     continue
    # }

    # if ($null -eq $target.list) {
    #     write-verbose "installing '$($target.name)'" -verbose
    #     install-mypackage $target
    # }
    # else {
    #     write-verbose "installing group '$module'" -verbose
    #     install-mygroup $target
    # }
}