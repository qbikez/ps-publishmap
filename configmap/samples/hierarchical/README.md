# Hierarchical Build Map Example

This example demonstrates the hierarchical structure support in ConfigMap, allowing you to organize build commands in logical groups and access them using dot notation.

## Structure

The build map is organized into the following groups:

- **frontend** - Frontend development commands (React/Vue/Angular)
- **backend** - Backend API development commands (.NET/Node.js)
- **database** - Database management commands
- **docker** - Docker and containerization commands  
- **deploy** - CI/CD and deployment commands
- **utils** - Utility commands used across the project

## Usage Examples

### Frontend Commands
```powershell
# Build frontend for production
qbuild frontend.build -Environment production

# Start development server
qbuild frontend.dev

# Run tests with watch mode
qbuild frontend.test -Watch

# Lint code with auto-fix
qbuild frontend.lint -Fix
```

### Backend Commands
```powershell
# Build backend in Release mode
qbuild backend.build -Configuration Release

# Run tests with coverage
qbuild backend.test -Coverage

# Start API in Production environment
qbuild backend.run -Environment Production

# Run database migrations
qbuild backend.migrate -Environment Staging
```

### Database Commands
```powershell
# Reset database (drop and recreate)
qbuild database.reset -Environment Development

# Seed database with sample data
qbuild database.seed

# Create database backup
qbuild database.backup -OutputPath "./backups/manual-backup.bak"
```

### Docker Commands
```powershell
# Build Docker images with custom tag
qbuild docker.build -Tag "v1.2.3" -NoCache

# Start containers in detached mode
qbuild docker.up -Detached -Profile production

# View logs for specific service
qbuild docker.logs -Service api -Follow

# Stop all containers
qbuild docker.down
```

### Deployment Commands
```powershell
# Deploy to staging
qbuild deploy.staging -Branch feature/new-feature

# Deploy to production (requires confirmation)
qbuild deploy.production -Tag "v1.2.3"

# Force production deployment (skip confirmation)
qbuild deploy.production -Tag "v1.2.3" -Force

# Rollback to previous version
qbuild deploy.rollback -Version "v1.2.2"
```

### Utility Commands
```powershell
# Clean all build artifacts
qbuild utils.clean

# Restore all dependencies
qbuild utils.restore

# Format code and check formatting
qbuild utils.format -Check
```

## Tab Completion

The hierarchical structure supports full tab completion:

```powershell
# Tab completion for groups
qbuild <TAB>
# Shows: frontend, backend, database, docker, deploy, utils

# Tab completion for commands within a group
qbuild frontend.<TAB>
# Shows: build, test, dev, lint

# Tab completion for parameters
qbuild frontend.build -<TAB>
# Shows: Environment

qbuild frontend.build -Environment <TAB>
# Shows: development, production
```

## Command List

To see all available commands with descriptions:

```powershell
qbuild list
```

This will show a formatted list of all commands organized by their hierarchical structure, including parameter information and descriptions.

## Benefits of Hierarchical Organization

1. **Logical Grouping** - Commands are organized by functional area
2. **Namespace Separation** - Avoid command name conflicts (e.g., frontend.build vs backend.build)
3. **Easier Discovery** - Related commands are grouped together
4. **Scalability** - Easy to add new command groups as projects grow
5. **Clear Intent** - Command paths clearly indicate what they do

## Integration with Existing Maps

Hierarchical maps can be mixed with flat maps. Non-hierarchical commands work exactly as before:

```powershell
$targets = @{
    # Flat command
    "quick-build" = { dotnet build }
    
    # Hierarchical group
    "advanced" = @{
        "full-build" = { 
            dotnet restore
            dotnet build --configuration Release
        }
    }
}
```

Both `qbuild quick-build` and `qbuild advanced.full-build` will work correctly.