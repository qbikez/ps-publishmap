pushd 

try {
    cd "src/publishmap.native"
    dotnet --info
    dotnet restore --verbosity Debug
    if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed" }
} finally {
    popd
}