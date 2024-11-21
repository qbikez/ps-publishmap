[CmdletBinding()]
param(
    [ArgumentCompleter({
            param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            ipmo "$PSScriptRoot/../../configmap.psm1"

            $modules = . "$PSScriptRoot/.configuration.map.ps1"

            $list = Get-CompletionList $modules
            return $list.Keys | ? { $_.startswith($wordToComplete) }
        })] 
    $module = $null
)
ipmo "$PSScriptRoot/../../configmap.psm1"

$modules = . "$PSScriptRoot/.configuration.map.ps1"
$list = Get-CompletionList $modules

$targets = $list.GetEnumerator() | ? { $_.key -in @($module) }
write-verbose "installing targets: $($targets.Keys)" -verbose

@($targets) | % {
    write-host "installing module '$($_.key)'"

    Invoke-ModuleCommand -module $_.value -key $_.Key
}