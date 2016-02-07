if (test-path "$artifacts\test-result.xml") {
    remove-item "$artifacts\test-result.xml"
}

& "$PSScriptRoot\test.ps1"

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
