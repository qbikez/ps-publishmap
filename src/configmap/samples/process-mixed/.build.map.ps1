#requires -version 7.0

# Mixed map: normal qbuild commands alongside qrun and qconf process entries.
# Try:
#   qbuild clean
#   qbuild build
#   qbuild bootstrap
#   qbuild bootstrap.prepare
#   qbuild storage
#   qbuild storage -value prod
#   qbuild list
#   qbuild !state

[ordered]@{
    "clean" = {
        Remove-Item -Recurse -Force ./out, ./workspace -ErrorAction Ignore
        Write-Host "cleaned out/ and workspace/" -ForegroundColor Gray
    }

    "build" = {
        param(
            [ValidateSet('Debug', 'Release')]
            [string]$Configuration = 'Debug'
        )

        $out = Join-Path (Get-Location) 'out'
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        "built:$Configuration" | Set-Content (Join-Path $out 'build.txt')
        Write-Host "wrote out/build.txt ($Configuration)" -ForegroundColor Green
    }

    "bootstrap" = [ordered]@{
        _settings   = @{ process = "qrun" }
        description = "Multi-step bootstrap with durable step state"

        "prepare"   = {
            $ws = Join-Path (Get-Location) 'workspace'
            New-Item -ItemType Directory -Path $ws -Force | Out-Null
            'prepared' | Set-Content (Join-Path $ws 'prepare.txt')
            Write-Host "  prepared workspace" -ForegroundColor Gray
        }

        "restore"   = {
            param(
                [ValidateSet('dev', 'prod')]
                [string]$Environment = 'dev'
            )

            $ws = Join-Path (Get-Location) 'workspace'
            if (!(Test-Path (Join-Path $ws 'prepare.txt'))) {
                throw "Run prepare first"
            }
            "restored:$Environment" | Set-Content (Join-Path $ws 'restore.txt')
            Write-Host "  restored ($Environment)" -ForegroundColor Gray
        }

        "verify"    = {
            $ws = Join-Path (Get-Location) 'workspace'
            if (!(Test-Path (Join-Path $ws 'restore.txt'))) {
                throw "Run restore first"
            }
            'ok' | Set-Content (Join-Path $ws 'verify.txt')
            Write-Host "  verified" -ForegroundColor Green
        }
    }

    "storage" = [ordered]@{
        _settings   = @{ process = "qconf" }
        description = "Storage endpoint configuration"
        options     = [ordered]@{
            local = "https://127.0.0.1:10000/devstoreaccount1"
            prod  = "https://storage.example"
        }
        get         = {
            param($ctx, $options)
            $stateFile = Join-Path (Get-Location) 'workspace/storage.txt'
            $key = if (Test-Path $stateFile) { (Get-Content $stateFile -Raw).Trim() } else { 'local' }
            $options[$key]
        }
        set         = {
            param($ctx, $key, $value)
            $workspace = Join-Path (Get-Location) 'workspace'
            New-Item -ItemType Directory -Path $workspace -Force | Out-Null
            $key | Set-Content (Join-Path $workspace 'storage.txt')
            Write-Host "  storage=$key ($value)" -ForegroundColor Green
        }
    }
}
