function Set-ModuleVersion(
    [parameter(mandatory = $true)]
    $path,
    [parameter(mandatory = $true)]
    [string]$version
) {
    if ($path.EndsWith(".psd1")) {
        $psd = $path
    }
    elseif ($path.EndsWith(".psm1")) {
        $psd = $path -replace ".psm1", ".psd1"
    }
    else {
        $modulename = Split-Path -Leaf $path
        $psd = "$path\$modulename.psd1"
    }
    if (!(Test-Path $psd)) {
        throw "psd1 file '$psd' not found"
    }

    $c = Get-Content $psd | Out-String 
    if ($c -match "ModuleVersion\s*=\s*'(.+)'") {
        Write-Host "replacing version $($Matches[1]) with $version in $psd"
    }
    else {
        throw "ModuleVersion not found in $psd"
    }
    $c = $c -replace "ModuleVersion\s*=\s*'.+'", "ModuleVersion = '$version'" 
    $c | Out-File $psd -Encoding utf8
}

function Get-ModuleVersion(
    [parameter(mandatory = $true)]
    $path
) {
    if ($path.EndsWith(".psd1")) {
        $psd = $path
    }
    elseif ($path.EndsWith(".psm1")) {
        $psd = $path -replace ".psm1", ".psd1"
    }
    else {
        $modulename = Split-Path -Leaf $path
        $psd = "$path\$modulename.psd1"
    }
    if (!(Test-Path $psd)) {
        throw "psd1 file '$psd' not found"
    }
    $c = Get-Content $psd | Out-String 
    if ($c -match "ModuleVersion\s=\s'(.+)'") {
        return $($Matches[1])
    }
    
    return $null
}
