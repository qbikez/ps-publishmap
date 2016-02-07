$pesterPath = "$psscriptroot\..\paket-files\pester\pester\pester.psm1"
$publishmapPath = "$psscriptroot\..\src\publishmap\publishmap.psm1"
import-module $pesterPath 
if ((get-module PublishMap) -ne $null) {
    write-host "reloading PublishMap module"
    remove-module PublishMap
}
import-module $publishmapPath
