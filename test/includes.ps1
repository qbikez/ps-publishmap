param([switch][bool]$internal = $false)

$pesterPath = "$psscriptroot\..\paket-files\pester\pester\pester.psm1"
$publishmapPath = "$psscriptroot\..\src\publishmap"
import-module $pesterPath

if ($internal) {    
    .  "$publishmapPath\imports.ps1"
} else {
    
    if ((get-module PublishMap) -ne $null) {
        write-host "reloading PublishMap module"
        remove-module PublishMap
    }
    import-module "$publishmapPath\PublishMap.psm1"
}

