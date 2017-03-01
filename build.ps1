pushd 

try {
    cd "src/publishmap/utils"
    cd "inheritance"
    dotnet publish
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }
} finally {
    popd
}