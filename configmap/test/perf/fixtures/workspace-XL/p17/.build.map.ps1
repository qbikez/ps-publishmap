[ordered]@{
    "build"  = {
        param(
            [ValidateSet('Debug', 'Release')]
            [string]$Configuration = 'Debug',
            [switch]$NoRestore,
            [string]$Framework
        )
        Write-Host "build $Configuration"
    }
    "test"   = @{
        exec        = { param([switch]$Watch, [string]$Filter) Write-Host "test" }
        description = "Run tests"
    }
    "tools"  = [ordered]@{
        "db"  = [ordered]@{
            "migrate" = @{
                exec        = { param([ValidateSet('up', 'down')][string]$Direction = 'up') Write-Host "migrate" }
                description = "Apply database migrations"
            }
            "seed"    = { Write-Host "seed" }
        }
        "fmt" = { param([switch]$Check) Write-Host "fmt" }
    }
    "deploy" = [ordered]@{
        _settings   = @{ process = "steps" }
        description = "Multi-step deploy"
        "package"   = @{ exec = { Write-Host "package" }; check = { $false } }
        "upload"    = { param([ValidateSet('dev', 'prod')][string]$Environment = 'dev') Write-Host "upload" }
        "verify"    = { Write-Host "verify" }
    }
    "env"    = [ordered]@{
        _settings   = @{ process = "options" }
        _template   = "dotenv:.env"
        description = "API settings in .env"
        options     = [ordered]@{
            local = [ordered]@{ "API_URL" = "http://localhost"; "API_KEY" = "dev" }
            prod  = [ordered]@{ "API_URL" = "https://api.example"; "API_KEY" = "prod" }
        }
    }
    "web"    = [ordered]@{
        _settings   = @{ process = "npm" }
        description = "package.json scripts"
    }
    "task1"  = { param([string]$Name = 'x1') Write-Host "task1" }
    "task2"  = { param([string]$Name = 'x2') Write-Host "task2" }
    "task3"  = { param([string]$Name = 'x3') Write-Host "task3" }
    "task4"  = { param([string]$Name = 'x4') Write-Host "task4" }
    "task5"  = { param([string]$Name = 'x5') Write-Host "task5" }
    "task6"  = { param([string]$Name = 'x6') Write-Host "task6" }
    "task7"  = { param([string]$Name = 'x7') Write-Host "task7" }
    "task8"  = { param([string]$Name = 'x8') Write-Host "task8" }
    "task9"  = { param([string]$Name = 'x9') Write-Host "task9" }
}
