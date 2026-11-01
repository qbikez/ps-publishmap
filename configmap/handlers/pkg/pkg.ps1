# Package-script proxy: _settings.process = 'bun' | 'npm' runs package.json scripts.
# package.json is read lazily (invoke, list, completion), never at map load.

function Get-PackageScriptEntryDirectory {
    param($Map, [string]$Entry)

    $mapEntry = Get-MapEntry $Map $Entry -language 'build' -OperationContext (New-ConfigMapOperationContext)
    if ($mapEntry -is [System.Collections.IDictionary] -and $mapEntry['_baseDir']) {
        return [string]$mapEntry['_baseDir']
    }
    if ($Map -is [System.Collections.IDictionary] -and $Map['_baseDir']) {
        return [string]$Map['_baseDir']
    }
    return (Get-Location).Path
}

function Get-PackageScripts {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $path = Join-Path $Directory 'package.json'
    if (!(Test-Path -LiteralPath $path)) {
        throw "package.json not found in '$Directory'."
    }

    $scripts = [ordered]@{}
    $package = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($package.scripts) {
        foreach ($property in $package.scripts.PSObject.Properties) {
            $scripts[$property.Name] = [string]$property.Value
        }
    }
    return $scripts
}

function Write-PackageScriptList {
    param([string]$Manager, [System.Collections.IDictionary]$Scripts)

    Write-Host ""
    Write-Host "$Manager scripts (package.json)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "COMMANDS:" -ForegroundColor Yellow
    $width = ($Scripts.Keys | Measure-Object -Property Length -Maximum).Maximum
    foreach ($item in $Scripts.GetEnumerator()) {
        Write-CommandHelpLine ([string]$item.Key) $item.Value '' $width
    }
}

function Invoke-PackageScriptProcess {
    param([Parameter(Mandatory = $true)][string]$Manager, [Parameter(Mandatory = $true)]$Context)

    $directory = Get-PackageScriptEntryDirectory -Map $Context.Map -Entry $Context.Entry
    $scripts = Get-PackageScripts -Directory $directory
    # ProcessAction is not positional, so a bare script name arrives in RemainingArguments.
    $passthrough = @(Get-ConfigMapProcessPassthrough -ProcessAction $Context.ProcessAction -ProcessValue $Context.ProcessValue -RemainingArguments $Context.RemainingArguments)
    $action = if ($passthrough.Count -gt 0) { $passthrough[0] }

    if (!$action -or $action -eq 'list') {
        Write-PackageScriptList -Manager $Manager -Scripts $scripts
        return
    }
    if (!$scripts.Contains($action)) {
        throw "Unknown $Manager script '$action'. Available: $($scripts.Keys -join ', ')"
    }

    $scriptArgs = @($passthrough | Select-Object -Skip 1)
    # npm forwards only what follows '--'; bun passes trailing arguments to the script as-is.
    if ($Manager -eq 'npm' -and $scriptArgs.Count -gt 0) {
        $scriptArgs = @('--') + $scriptArgs
    }

    Push-Location -LiteralPath $directory
    try {
        & $Manager run $action @scriptArgs
    }
    finally {
        Pop-Location
    }
}

$packageInitConditions = @{
    bun = { param($Directory) Test-Path -LiteralPath (Join-Path $Directory 'bun.lock') }
    npm = {
        param($Directory)
        (Test-Path -LiteralPath (Join-Path $Directory 'package.json')) -and
        !(Test-Path -LiteralPath (Join-Path $Directory 'bun.lock'))
    }
}

foreach ($packageManager in 'bun', 'npm') {
    $manager = $packageManager
    Register-ConfigMapProcess -Name $manager `
        -InitTemplate "$PSScriptRoot/$manager.init.map.ps1" `
        -InitCondition $packageInitConditions[$manager] `
        -Invoke { param($Context) Invoke-PackageScriptProcess -Manager (Get-ConfigMapSettingsForPath -Map $Context.Map -Path $Context.Entry).Process -Context $Context } `
        -GetDynamicParam { param($Context) $null } `
        -WriteListEntry {
        param($ListContext)
        $name = (Get-ConfigMapSettingsForPath -Map $ListContext.Map -Path $ListContext.Name).Process
        $description = if ($ListContext.Entry['description']) { $ListContext.Entry['description'] } else { "Run $name scripts from package.json" }
        Write-CommandHelpLine $ListContext.Name $description '' 0
    } `
        -Complete {
        param($CompleteContext)
        if ($CompleteContext.Position -ne 'Action') { return @() }
        $directory = Get-PackageScriptEntryDirectory -Map $CompleteContext.Map -Entry $CompleteContext.Entry
        try { $names = @((Get-PackageScripts -Directory $directory).Keys) } catch { $names = @() }
        @('list') + $names | Where-Object { $_ -like "$($CompleteContext.Word)*" }
    }
}
Remove-Variable packageManager, manager, packageInitConditions
