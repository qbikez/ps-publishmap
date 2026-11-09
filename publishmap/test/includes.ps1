param([switch][bool]$internal = $false)

$publishmapPath = Join-Path $PSScriptRoot ".."

if ($internal) {
    . (Join-Path $publishmapPath "imports.ps1")
} else {
    if ($null -ne (get-module PublishMap)) {
        write-information "reloading PublishMap module"
        remove-module PublishMap
    }
    import-module (Join-Path $publishmapPath "publishmap.psm1")
}
