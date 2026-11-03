#requires -version 7.0

# Simulated app bootstrap / release pipeline for qrun.
# Artifacts land under ./workspace relative to this sample directory.

function Get-QRunSampleRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    return (Get-Location).Path
}

function Get-QRunWorkspace {
    Join-Path (Get-QRunSampleRoot) 'workspace'
}

function Write-QRunStep {
    param([string]$Message, [string]$Color = 'Gray')
    Write-Host "  · $Message" -ForegroundColor $Color
}

function Assert-QRunFile {
    param([string]$Path, [string]$Hint)
    if (!(Test-Path -LiteralPath $Path)) {
        throw "$Hint (missing: $Path)"
    }
}

[ordered]@{
    # Full local bootstrap: prepare dirs → config → deps → build → smoke test → package
    "bootstrap" = [ordered]@{
        description    = "Bootstrap a simulated app workspace from scratch"

        "prepare"      = {
            $ws = Get-QRunWorkspace
            @(
                $ws
                (Join-Path $ws 'src')
                (Join-Path $ws 'config')
                (Join-Path $ws 'artifacts')
            ) | ForEach-Object {
                New-Item -ItemType Directory -Path $_ -Force | Out-Null
            }
            Write-QRunStep "workspace ready at $ws" Green
        }

        "write-config" = {
            param(
                [ValidateSet('dev', 'staging', 'prod')]
                [string]$Environment = 'dev'
            )

            $ws = Get-QRunWorkspace
            $configPath = Join-Path $ws 'config' 'appsettings.json'
            $config = [ordered]@{
                environment = $Environment
                createdAt   = (Get-Date).ToString('o')
                features    = @{
                    logging = $true
                    cache   = ($Environment -ne 'dev')
                }
            }
            $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding utf8
            Write-QRunStep "wrote config for '$Environment' → $configPath" Green
        }

        "restore"      = {
            $ws = Get-QRunWorkspace
            Assert-QRunFile (Join-Path $ws 'config' 'appsettings.json') "Run write-config first"

            $lockPath = Join-Path $ws 'src' 'packages.lock'
            @(
                'contoso.logging@1.2.0'
                'contoso.cache@2.0.1'
                'contoso.http@3.4.0'
            ) | Set-Content -LiteralPath $lockPath -Encoding utf8

            Start-Sleep -Milliseconds 150
            Write-QRunStep "restored $((Get-Content $lockPath).Count) packages" Green
        }

        "compile"      = {
            param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug')

            $ws = Get-QRunWorkspace
            Assert-QRunFile (Join-Path $ws 'src' 'packages.lock') "Run restore first"

            $srcPath = Join-Path $ws 'src' 'Program.ps1'
            @(
                "# generated $Configuration build"
                "Write-Output 'Hello from Contoso sample'"
            ) | Set-Content -LiteralPath $srcPath -Encoding utf8

            $binDir = Join-Path $ws 'artifacts' $Configuration
            New-Item -ItemType Directory -Path $binDir -Force | Out-Null
            Copy-Item -LiteralPath $srcPath -Destination (Join-Path $binDir 'app.ps1') -Force

            $manifest = [ordered]@{
                configuration = $Configuration
                builtAt       = (Get-Date).ToString('o')
                entrypoint    = 'app.ps1'
            }
            $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $binDir 'build.json') -Encoding utf8
            Write-QRunStep "compiled $Configuration → $binDir" Green
        }

        "smoke-test"   = {
            param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug')

            $ws = Get-QRunWorkspace
            $app = Join-Path $ws 'artifacts' $Configuration 'app.ps1'
            Assert-QRunFile $app "Run compile -$Configuration first"

            $output = & $app
            if ($output -notmatch 'Hello from Contoso') {
                throw "smoke-test failed: unexpected output '$output'"
            }

            $resultPath = Join-Path $ws 'artifacts' $Configuration 'smoke.json'
            @{ passed = $true; output = "$output"; at = (Get-Date).ToString('o') } |
                ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding utf8
            Write-QRunStep "smoke-test passed ($output)" Green
        }

        "package"      = {
            param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug')

            $ws = Get-QRunWorkspace
            $binDir = Join-Path $ws 'artifacts' $Configuration
            Assert-QRunFile (Join-Path $binDir 'smoke.json') "Run smoke-test first"

            $zipPath = Join-Path $ws 'artifacts' "contoso-$Configuration.zip"
            if (Test-Path -LiteralPath $zipPath) {
                Remove-Item -LiteralPath $zipPath -Force
            }
            Compress-Archive -Path (Join-Path $binDir '*') -DestinationPath $zipPath
            Write-QRunStep "packaged → $zipPath" Green
        }
    }

    # Shorter process that intentionally fails mid-way so you can demo resume
    "release"   = [ordered]@{
        description = "Release checklist (step 'gate' fails until ./workspace/APPROVED exists)"
        exec        = @('tag', 'notes', 'gate', 'publish')

        "tag"       = {
            $ws = Get-QRunWorkspace
            New-Item -ItemType Directory -Path $ws -Force | Out-Null
            $tag = "v0.$((Get-Date).ToString('MMdd.HHmm'))"
            $tag | Set-Content -LiteralPath (Join-Path $ws 'VERSION') -Encoding utf8
            Write-QRunStep "tagged $tag" Green
        }

        "notes"     = {
            $ws = Get-QRunWorkspace
            Assert-QRunFile (Join-Path $ws 'VERSION') "Run tag first"
            $version = (Get-Content (Join-Path $ws 'VERSION') -Raw).Trim()
            @"
# Release $version

- bootstrap artifacts verified
- awaiting approval gate
"@ | Set-Content -LiteralPath (Join-Path $ws 'CHANGELOG.md') -Encoding utf8
            Write-QRunStep "wrote CHANGELOG.md for $version" Green
        }

        "gate"      = {
            $ws = Get-QRunWorkspace
            $approved = Join-Path $ws 'APPROVED'
            if (!(Test-Path -LiteralPath $approved)) {
                throw "Release not approved. Create '$approved' (e.g. Set-Content $approved 'ok') then re-run: qrun release"
            }
            Write-QRunStep "approval gate passed" Green
        }

        "publish"   = {
            $ws = Get-QRunWorkspace
            Assert-QRunFile (Join-Path $ws 'CHANGELOG.md') "Run notes first"
            Assert-QRunFile (Join-Path $ws 'APPROVED') "Run gate first"

            $version = (Get-Content (Join-Path $ws 'VERSION') -Raw).Trim()
            $publishDir = Join-Path $ws 'publish'
            New-Item -ItemType Directory -Path $publishDir -Force | Out-Null
            Copy-Item (Join-Path $ws 'CHANGELOG.md') (Join-Path $publishDir 'CHANGELOG.md') -Force
            Copy-Item (Join-Path $ws 'VERSION') (Join-Path $publishDir 'VERSION') -Force
            @{ version = $version; publishedAt = (Get-Date).ToString('o') } |
                ConvertTo-Json | Set-Content (Join-Path $publishDir 'publish.json') -Encoding utf8
            Write-QRunStep "published $version → $publishDir" Green
        }
    }

    # Cleanup helper process
    "clean"     = [ordered]@{
        description = "Remove the sample workspace and process state"

        "workspace" = {
            $ws = Get-QRunWorkspace
            if (Test-Path -LiteralPath $ws) {
                Remove-Item -LiteralPath $ws -Recurse -Force
                Write-QRunStep "removed $ws" Yellow
            }
            else {
                Write-QRunStep "workspace already clean" DarkGray
            }
        }

        "state"     = {
            $stateRoot = Join-Path (Get-QRunSampleRoot) '.configmap'
            if (Test-Path -LiteralPath $stateRoot) {
                Remove-Item -LiteralPath $stateRoot -Recurse -Force
                Write-QRunStep "removed $stateRoot" Yellow
            }
            else {
                Write-QRunStep "no process state to remove" DarkGray
            }
        }
    }
}
