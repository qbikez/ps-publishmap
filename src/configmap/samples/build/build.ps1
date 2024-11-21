[CmdletBinding()]
param(
    [ArgumentCompleter({
            param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            ipmo "$PSScriptRoot/../../configmap.psm1"

            $modules = . "$PSScriptRoot/.build.map.ps1"

            $list = Get-CompletionList $modules
            return $list.Keys | ? { $_.startswith($wordToComplete) }
        })] 
    $module = $null
)
DynamicParam {
    if (!$module) { return @() }
    
    $key = $module
    $bound = $PSBoundParameters
    
    ipmo "$PSScriptRoot/../../configmap.psm1"
    $map = . "$PSScriptRoot/.build.map.ps1"
    $selectedModule = Get-MapModule $map $key
    if (!$selectedModule) { return @() }
    $command = Get-ModuleCommand $selectedModule $key
    if (!$command) { return @() }
    $p = Get-ScriptArgs $command

    return $p
}

process {
    ipmo "$PSScriptRoot/../../configmap.psm1"

    $map = . "$PSScriptRoot/.build.map.ps1"
    $targets = Get-MapModules $map $module
    write-verbose "running targets: $($targets.Key)"

    @($targets) | % {
        Write-Verbose "running module '$($_.key)'"

        $bound = $PSBoundParameters
        Invoke-ModuleCommand -module $_.value -key $_.Key @{ bound = $bound }
    }
}