$pesterPath = "$psscriptroot\..\paket-files\pester\pester\pester.psm1"

import-module $pesterPath 

$artifacts = "$psscriptroot\..\artifacts"
if (!(Test-Path $artifacts)) {
    new-item $artifacts -ItemType directory
}
Invoke-Pester "$psscriptroot\..\test\test.ps1" -OutputFile $artifacts\test-result.xml -OutputFormat NUnitXml

write-host "artifacts:"
gc "$artifacts\test-result.xml" 

$url = "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)"
#$url = https://ci.appveyor.com/api/testresults/nunit/bq558ckwevwb47qb
write-host "uploading test result to $url"
# upload results to AppVeyor
$wc = New-Object 'System.Net.WebClient'

try {
    $r = $wc.UploadFile($url, ("$artifacts\test-result.xml"))
    
write-host "upload done. result = $r"
} 
finally {
    $wc.Dispose()
}
