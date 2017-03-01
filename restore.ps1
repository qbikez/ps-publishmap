pushd 

try {
    cd "src/publishmap/utils"
    dotnet --info
    dotnet restore --verbosity Debug
    if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed" }
} finally {
    popd
}