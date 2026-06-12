# Tmux integration sample
# When qbuild runs inside tmux, each entry is dispatched to a window named after
# the entry path (e.g. build.ui, test.unit). See README.md for details.

$targets = @{
    "build" = @{
        "ui" = @{
            exec = {
                param([ValidateSet("Debug", "Release")]$Configuration = "Debug")
                Write-Host "[$Configuration] Building UI..." -ForegroundColor Cyan
                Start-Sleep -Seconds 2
                Write-Host "UI build finished." -ForegroundColor Green
            }
            description = "Build frontend (runs in tmux window 'build.ui')"
        }

        "api" = @{
            exec = {
                param([ValidateSet("Debug", "Release")]$Configuration = "Debug")
                Write-Host "[$Configuration] Building API..." -ForegroundColor Cyan
                Start-Sleep -Seconds 2
                Write-Host "API build finished." -ForegroundColor Green
            }
            description = "Build backend API (runs in tmux window 'build.api')"
        }
    }

    "test" = @{
        "unit" = {
            param([switch]$Watch)
            Write-Host "Running unit tests$(if ($Watch) { ' (watch)' })..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            Write-Host "Unit tests passed." -ForegroundColor Green
        }

        "integration" = {
            Write-Host "Running integration tests..." -ForegroundColor Yellow
            Start-Sleep -Seconds 3
            Write-Host "Integration tests passed." -ForegroundColor Green
        }
    }

    "dev" = @{
        "ui" = {
            Write-Host "Starting UI dev server (Ctrl+C to stop)..." -ForegroundColor Magenta
            1..5 | ForEach-Object {
                Write-Host "  [ui] serving on http://localhost:3000 (tick $_)"
                Start-Sleep -Seconds 1
            }
        }

        "api" = {
            Write-Host "Starting API dev server (Ctrl+C to stop)..." -ForegroundColor Magenta
            1..5 | ForEach-Object {
                Write-Host "  [api] listening on http://localhost:5000 (tick $_)"
                Start-Sleep -Seconds 1
            }
        }
    }
}

return $targets
