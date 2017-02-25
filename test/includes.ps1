param([switch][bool]$internal = $false)

$publishmapPath = "$psscriptroot\..\src\publishmap"
import-module Pester

# $inputDir = "$psscriptroot\input"

if ($internal) {    
    .  "$publishmapPath\imports.ps1"
} else {
    if ($null -ne (get-module PublishMap)) {
        write-information "reloading PublishMap module"
        remove-module PublishMap
    }
    import-module "$publishmapPath\PublishMap.psm1"
}

