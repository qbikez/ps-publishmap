$pesterPath = "$psscriptroot\..\paket-files\pester\pester\pester.psm1"

import-module $pesterPath 

$artifacts = "$psscriptroot\..\artifacts"
if (!(Test-Path $artifacts)) {
    new-item $artifacts -ItemType directory
}
Invoke-Pester "$psscriptroot\..\test\test.ps1" -OutputFile $artifacts\test-result.xml -OutputFormat NUnitXml
