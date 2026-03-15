$script:samplesPath = "$PSScriptRoot/../../samples"

function Initialize-ConfigMap([Parameter(Mandatory = $true)] $file) {
    if (Test-Path $file) {
        throw "map file '$file' already exists"
    }

    $defaultConfig = Get-Content $script:samplesPath/_default/.configuration.map.ps1
    Write-Host "Initializing configmap file '$file'"
    $defaultConfig | Out-File $file

    $fullPath = (Get-Item $file).FullName
    $dir = Split-Path $fullPath -Parent
    $defaultUtils = Get-Content $script:samplesPath/_default/.config-utils.ps1
    $defaultUtils | Out-File (Join-Path $dir ".config-utils.ps1")
}


function Initialize-BuildMap([Parameter(Mandatory = $true)] $file) {
    if (Test-Path $file) {
        throw "map file '$file' already exists"
    }

    $defaultConfig = Get-Content $script:samplesPath/_default/.build.map.ps1 -Raw
    $dir = Split-Path (Join-Path (Get-Location) $file) -Parent
    $packageJsonPath = Join-Path $dir "package.json"

    $npmBlock = ""
    if (Test-Path $packageJsonPath) {
        try {
            $pkg = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
            if ($pkg.scripts -and ($pkg.scripts.PSObject.Properties | Measure-Object).Count -gt 0) {
                $lines = @()
                foreach ($prop in $pkg.scripts.PSObject.Properties) {
                    $scriptName = $prop.Name
                    # Use single quotes so special chars in script names (e.g. test:unit) are safe
                    $lines += "        `"$($scriptName.Replace('"', '`"'))`" = { npm run '$($scriptName.Replace("'", "''"))' }"
                }
                $n = [System.Environment]::NewLine
                $npmBlock = "$n    `"npm`" = [ordered]@{$n" + ($lines -join $n) + "$n    }"
                Write-Host "Added npm entry with $($lines.Count) script(s) from package.json"
            }
        }
        catch {
            Write-Warning "Could not parse package.json: $_"
        }
    }

    $placeholder = "# NPM_SCRIPTS_PLACEHOLDER"
    if ($npmBlock) {
        $defaultConfig = $defaultConfig.Replace($placeholder, $npmBlock)
    }
    else {
        $defaultConfig = $defaultConfig -replace "(\r?\n)\s+$([regex]::Escape($placeholder))", ""
    }

    Write-Host "Initializing buildmap file '$file'"
    $defaultConfig | Out-File $file
}
