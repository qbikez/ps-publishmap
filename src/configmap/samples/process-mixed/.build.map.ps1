#requires -version 7.0

# Mixed map: normal qbuild commands alongside process=qrun multi-step entries.
# Try:
#   qbuild clean
#   qbuild build
#   qbuild bootstrap
#   qbuild bootstrap.prepare
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
        process     = "qrun"
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
}
