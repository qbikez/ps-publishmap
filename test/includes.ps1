param([switch][bool]$internal = $false)

$publishmapPath = "$psscriptroot\..\src\publishmap"
import-module Pester

$inputDir = "$psscriptroot\input"

if ($internal) {    
    .  "$publishmapPath\imports.ps1"
} else {
    
    if ((get-module $null -ne PublishMap)) {
        write-host "reloading PublishMap module"
        remove-module PublishMap
    }
    import-module "$publishmapPath\PublishMap.psm1"
}

