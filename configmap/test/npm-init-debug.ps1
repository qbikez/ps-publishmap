$dir = Join-Path $env:TEMP "npm-init-debug"
New-Item -ItemType Directory -Path $dir -Force | Out-Null
'{"name":"x","version":"1.0.0","scripts":{"build":"echo b","test":"echo t"}}' | Set-Content (Join-Path $dir "package.json") -Encoding utf8
Push-Location $dir
try {
    Import-Module "$PSScriptRoot\..\configmap.psm1" -Force
    qbuild "!init"
    Get-Content ".build.map.ps1" -Raw
} finally {
    Pop-Location
}
