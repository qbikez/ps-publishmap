pushd 

try {
    cd "src/publishmap.native"
    cd "publishmap.core"
    dotnet build
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

    $libpath = "..\..\publishmap\lib"
    if (!(test-path $libpath)) { $null = new-item -type directory "..\..\publishmap\lib" }
    copy "bin\Debug\net451\*" $libpath

} finally {
    popd
}