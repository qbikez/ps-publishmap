ipmo require
req process

pushd
try {
    cd "src/publishmap.native/publishmap.test"
    invoke dotnet test
} finally {
    popd
}

if ($env:APPVEYOR_JOB_ID -ne $null) {
    & "scripts/lib/test.appveyor.ps1"
} else {
    & "scripts/lib/test.ps1"
}

