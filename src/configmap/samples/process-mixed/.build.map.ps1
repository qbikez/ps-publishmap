#requires -version 7.0

# Mixed map: normal qbuild commands alongside steps and options process entries.
# Try:
#   qbuild clean
#   qbuild build
#   qbuild bootstrap
#   qbuild bootstrap.prepare
#   qbuild provision            # forceCheck: re-checks real state on every run
#   qbuild storage
#   qbuild storage -value prod
#   qbuild endpoint
#   qbuild endpoint -value prod
#   qbuild env set dev -tenant abc
#   qbuild env get
#   qbuild list
#   qbuild !state

[ordered]@{
    "clean"             = {
        Remove-Item -Recurse -Force ./out, ./workspace -ErrorAction Ignore
        Write-Host "cleaned out/ and workspace/" -ForegroundColor Gray
    }

    "build"             = {
        param(
            [ValidateSet('Debug', 'Release')]
            [string]$Configuration = 'Debug'
        )

        $out = Join-Path (Get-Location) 'out'
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        "built:$Configuration" | Set-Content (Join-Path $out 'build.txt')
        Write-Host "wrote out/build.txt ($Configuration)" -ForegroundColor Green
    }

    "bootstrap"         = [ordered]@{
        _settings   = @{ process = "steps" }
        description = "Multi-step bootstrap with durable step state"

        # `qbuild bootstrap -check` runs `check` handlers instead of trusting cached state
        # (a `check` on "bootstrap" itself would replace the per-step checks).
        "prepare"   = @{
            exec  = {
                $ws = Join-Path (Get-Location) 'workspace'
                New-Item -ItemType Directory -Path $ws -Force | Out-Null
                'prepared' | Set-Content (Join-Path $ws 'prepare.txt')
                Write-Host "  prepared workspace" -ForegroundColor Gray
            }
            check = { Test-Path (Join-Path (Get-Location) 'workspace/prepare.txt') }
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

    "provision"         = [ordered]@{
        # forceCheck runs the `check` handlers before every run instead of trusting
        # cached state, so deleting workspace/tools re-runs "tools" on the next run.
        _settings   = @{ process = "steps"; forceCheck = $true }
        description = "Steps that re-verify real state on every run"

        "tools"     = @{
            exec  = {
                $tools = Join-Path (Get-Location) 'workspace/tools'
                New-Item -ItemType Directory -Path $tools -Force | Out-Null
                'installed' | Set-Content (Join-Path $tools 'tool.txt')
                Write-Host "  installed tools" -ForegroundColor Gray
            }
            check = { Test-Path (Join-Path (Get-Location) 'workspace/tools/tool.txt') }
        }

        "config"    = @{
            exec  = {
                $ws = Join-Path (Get-Location) 'workspace'
                New-Item -ItemType Directory -Path $ws -Force | Out-Null
                'configured' | Set-Content (Join-Path $ws 'provision.cfg')
                Write-Host "  wrote provision.cfg" -ForegroundColor Gray
            }
            check = { Test-Path (Join-Path (Get-Location) 'workspace/provision.cfg') }
        }
    }

    "storage"           = [ordered]@{
        _settings   = @{ process = "options" }
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

    "endpoint"          = [ordered]@{
        _settings   = @{ process = "options" }
        _template   = "appsettings:appsettings.Development.json"
        description = "Appsettings storage endpoint (appconfig template)"
        options     = [ordered]@{
            local = [ordered]@{
                "Storage:BaseUrl" = "https://127.0.0.1:10000/devstoreaccount1"
            }
            prod  = [ordered]@{
                "Storage:BaseUrl" = "https://storage.example"
            }
        }
    }

    "endpoint_override" = [ordered]@{
        _settings   = @{ process = "options" }
        _template   = "appsettings:appsettings.Development.json"
        description = "Appsettings storage endpoint (appconfig template)"
        options     = [ordered]@{
            local = [ordered]@{
                "Storage:BaseUrl" = "https://127.0.0.1:10000/devstoreaccount1"
            }
            prod  = [ordered]@{
                "Storage:BaseUrl" = "https://storage.example"
            }
        }

        set         = {
            param($ctx, $key, $value, $_context)

            # Call the inherited appsettings template set, then do extra work.
            & $_context.base.set $ctx $key $value $_context

            Write-Host "additional something"
        }
    }

    "api"               = [ordered]@{
        _settings   = @{ process = "options" }
        _template   = "dotenv:.env"
        description = "API settings in .env (dotenv template)"
        options     = [ordered]@{
            local = [ordered]@{
                "API_URL" = "http://localhost:5000"
                "API_KEY" = "dev-key"
            }
            prod  = [ordered]@{
                "API_URL" = "https://api.example.com"
                "API_KEY" = "prod-key"
            }
        }
    }

    "env"               = [ordered]@{
        _settings   = @{ process = "options" }
        description = "Environment / tenant selection (opaque -tenant)"
        options     = [ordered]@{
            local = "local"
            dev   = "dev"
            prod  = "prod"
        }
        get         = {
            param($ctx, $options)
            $keyFile = Join-Path (Get-Location) 'workspace/env-key.txt'
            if (Test-Path $keyFile) {
                $key = (Get-Content $keyFile -Raw).Trim()
                if ($options.Contains($key)) { return $options[$key] }
            }
            $tenantFile = Join-Path (Get-Location) 'workspace/env.txt'
            if (Test-Path $tenantFile) {
                (Get-Content $tenantFile -Raw).Trim()
            }
            else {
                ''
            }
        }
        set         = {
            param($ctx, $key, $value, [string]$tenant)
            if ([string]::IsNullOrWhiteSpace($tenant)) {
                throw "Set env requires -tenant <name>."
            }
            $workspace = Join-Path (Get-Location) 'workspace'
            New-Item -ItemType Directory -Path $workspace -Force | Out-Null
            $key | Set-Content (Join-Path $workspace 'env-key.txt')
            $tenant | Set-Content (Join-Path $workspace 'env.txt')
            Write-Host "  env=$key tenant=$tenant" -ForegroundColor Green
        }
    }
}
