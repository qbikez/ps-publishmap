pushd 

try {
    cd "src/publishmap/utils"
    dotnet --info
    dotnet restore
    if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed" }
    cd "inheritance"
    dotnet publish
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }
} finally {
    popd
}