# Hierarchical Build Map Example
# This demonstrates the new hierarchical structure support in configmap
# You can organize commands in nested groups and access them with dot notation

$targets = @{
    # Frontend development commands
    "frontend" = @{
        "build" = @{
            exec = {
                param([ValidateSet("development", "production")]$Environment = "development")
                Write-Host "Building frontend for $Environment environment..."
                if ($Environment -eq "production") {
                    npm run build:prod
                } else {
                    npm run build:dev
                }
            }
            description = "Build frontend application"
        }
        
        "test" = {
            param([switch]$Watch, [string]$Filter)
            Write-Host "Running frontend tests..."
            $args = @("test")
            if ($Watch) { $args += "--watch" }
            if ($Filter) { $args += "--testNamePattern", $Filter }
            npm run @args
        }
        
        "dev" = {
            Write-Host "Starting frontend development server..."
            npm run dev
        }
        
        "lint" = {
            param([switch]$Fix)
            Write-Host "Linting frontend code..."
            $args = @("run", "lint")
            if ($Fix) { $args += "--fix" }
            npm @args
        }
    }
    
    # Backend development commands  
    "backend" = @{
        "build" = @{
            exec = {
                param([ValidateSet("Debug", "Release")]$Configuration = "Debug")
                Write-Host "Building backend with $Configuration configuration..."
                dotnet build --configuration $Configuration --no-restore
            }
            description = "Build backend API"
        }
        
        "test" = {
            param([switch]$Coverage, [string]$Filter)
            Write-Host "Running backend tests..."
            $args = @("test", "--no-build")
            if ($Coverage) { $args += "--collect:`"XPlat Code Coverage`"" }
            if ($Filter) { $args += "--filter", $Filter }
            dotnet @args
        }
        
        "run" = {
            param([string]$Environment = "Development")
            Write-Host "Starting backend API in $Environment environment..."
            $env:ASPNETCORE_ENVIRONMENT = $Environment
            dotnet run --no-build
        }
        
        "migrate" = {
            param([string]$Environment = "Development")
            Write-Host "Running database migrations for $Environment..."
            $env:ASPNETCORE_ENVIRONMENT = $Environment
            dotnet ef database update
        }
    }
    
    # Database management commands
    "database" = @{
        "reset" = {
            param([string]$Environment = "Development")
            Write-Host "Resetting database for $Environment environment..."
            $env:ASPNETCORE_ENVIRONMENT = $Environment
            dotnet ef database drop --force
            dotnet ef database update
        }
        
        "seed" = {
            param([string]$Environment = "Development")
            Write-Host "Seeding database with sample data..."
            $env:ASPNETCORE_ENVIRONMENT = $Environment
            dotnet run --project Tools/DataSeeder
        }
        
        "backup" = {
            param([string]$OutputPath = "./backups/$(Get-Date -Format 'yyyyMMdd-HHmmss').bak")
            Write-Host "Creating database backup at $OutputPath..."
            # Database backup logic here
            Write-Host "Backup created successfully"
        }
    }
    
    # Docker and deployment commands
    "docker" = @{
        "build" = {
            param([string]$Tag = "latest", [switch]$NoCache)
            Write-Host "Building Docker images with tag: $Tag"
            $args = @("build", "-t", "myapp:$Tag")
            if ($NoCache) { $args += "--no-cache" }
            $args += "."
            docker @args
        }
        
        "up" = {
            param([switch]$Detached, [string]$Profile = "development")
            Write-Host "Starting Docker containers with profile: $Profile"
            $args = @("compose", "--profile", $Profile, "up")
            if ($Detached) { $args += "-d" }
            docker @args
        }
        
        "down" = {
            Write-Host "Stopping Docker containers..."
            docker compose down
        }
        
        "logs" = {
            param([string]$Service, [switch]$Follow)
            $args = @("compose", "logs")
            if ($Follow) { $args += "-f" }
            if ($Service) { $args += $Service }
            docker @args
        }
    }
    
    # CI/CD and deployment commands
    "deploy" = @{
        "staging" = {
            param([string]$Branch = "develop")
            Write-Host "Deploying $Branch branch to staging environment..."
            # Staging deployment logic
            Write-Host "Staging deployment completed"
        }
        
        "production" = {
            param([string]$Tag, [switch]$Force)
            if (!$Tag) {
                throw "Tag parameter is required for production deployment"
            }
            Write-Host "Deploying tag $Tag to production..."
            if (!$Force) {
                $confirm = Read-Host "Are you sure you want to deploy to production? (y/N)"
                if ($confirm -ne "y") {
                    Write-Host "Deployment cancelled"
                    return
                }
            }
            # Production deployment logic
            Write-Host "Production deployment completed"
        }
        
        "rollback" = {
            param([string]$Version)
            if (!$Version) {
                throw "Version parameter is required for rollback"
            }
            Write-Host "Rolling back to version $Version..."
            # Rollback logic
            Write-Host "Rollback completed"
        }
    }
    
    # Utility commands that can be used across the project
    "utils" = @{
        "clean" = {
            Write-Host "Cleaning build artifacts..."
            Remove-Item "bin", "obj", "node_modules/.cache" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Clean completed"
        }
        
        "restore" = {
            Write-Host "Restoring dependencies..."
            dotnet restore
            npm install
            Write-Host "Dependencies restored"
        }
        
        "format" = {
            param([switch]$Check)
            Write-Host "Formatting code..."
            $args = @("format")
            if ($Check) { $args += "--verify-no-changes" }
            dotnet @args
            npm run prettier
        }
    }
}

return $targets