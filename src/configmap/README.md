# ConfigMap

ConfigMap is a PowerShell module that extends publishmap functionality to provide build and configuration management capabilities through declarative map files. Execute build scripts and manage configurations with simple commands like `qbuild` and `qconf`.

## Quick Start

1. **Install the module:**
   ```powershell
   Import-Module configmap
   ```

2. **Initialize a build map:**
   ```powershell
   qbuild init
   ```
   This creates a `.build.map.ps1` file with sample build scripts.

3. **List available commands:**
   ```powershell
   qbuild          # Shows all available build commands
   qbuild help     # Shows help information
   ```

4. **Run build commands:**
   ```powershell
   qbuild build    # Runs the build script
   qbuild test     # Runs the test script
   qbuild clean    # Runs the clean script
   ```

5. **Use with parameters:**
   ```powershell
   qbuild build -Configuration Release
   qbuild deploy -Environment staging
   ```

## Sample Map File

Here's a sample build map file (`.build.map.ps1`):

```powershell
@{
    # Simple script block - just PowerShell code
    "clean" = {
        Remove-Item "bin", "obj" -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Command object with exec and description
    "restore" = @{
        exec = {
            dotnet restore
        }
        description = "Restore NuGet packages"
    }
    
    # Command with parameters
    "build" = @{
        exec = {
            param([string]$Configuration = "Debug")
            dotnet build --configuration $Configuration --no-restore
        }
        description = "Build the project"
    }
    
    # Command with multiple parameters including switches
    "test" = @{
        exec = {
            param([switch]$Coverage, [string]$Filter)
            $args = @("test", "--no-build")
            if ($Coverage) { $args += "--collect:`"XPlat Code Coverage`"" }
            if ($Filter) { $args += "--filter", $Filter }
            & dotnet @args
        }
        description = "Run unit tests"
    }
    
    # Advanced command with typed parameters and validation
    "deploy" = @{
        exec = {
            param(
                [ValidateSet("dev", "staging", "prod")]$Environment = "dev",
                [switch]$Force,
                [int]$Timeout = 300
            )
            Write-Host "Deploying to $Environment environment (timeout: ${Timeout}s)..."
            if ($Force) { Write-Host "Force deployment enabled" }
            # Deployment logic here
        }
        description = "Deploy to specified environment"
    }
}
```

### Advanced Map Features

- **Parameters**: Commands can accept typed parameters with defaults
- **Script Blocks**: Direct PowerShell execution with full language support
- **Command Objects**: Structured entries with `exec`, `description`, and other properties
- **Dynamic Execution**: Commands are evaluated at runtime with current context

### Usage Examples

```powershell
# Basic commands
qbuild clean
qbuild restore
qbuild build

# Commands with parameters
qbuild build -Configuration Release
qbuild test -Coverage -Filter "Category=Unit"
qbuild deploy -Environment prod -Force -Timeout 600
```

## Autocompletion

ConfigMap provides rich tab completion for `qbuild` commands:

### Command Completion
```powershell
qbuild <TAB>              # Shows: clean, restore, build, test, deploy
qbuild bu<TAB>            # Completes to: build
qbuild de<TAB>            # Completes to: deploy
```

### Parameter Completion
```powershell
qbuild build -<TAB>                     # Shows: Configuration
qbuild test -<TAB>                      # Shows: Coverage, Filter
qbuild deploy -<TAB>                    # Shows: Environment, Force, Timeout
qbuild deploy -Environment <TAB>        # Shows: dev, staging, prod
```

### Setup Autocompletion

Autocompletion works automatically when the configmap module is imported:

1. **Add to your PowerShell profile:**
   ```powershell
   Import-Module configmap
   ```

2. **Verify completion is working:**
   ```powershell
   qbuild <TAB>    # Should show available commands
   ```

### Dynamic Parameter Discovery

ConfigMap automatically discovers parameters from your script blocks:

```powershell
@{
    "deploy" = @{
        exec = {
            param(
                [string]$Environment = "dev",
                [switch]$Force,
                [ValidateSet("fast", "full")]$Mode = "fast"
            )
            # Deployment logic
        }
    }
}
```

Tab completion will automatically provide:
- `-Environment` with no suggestions (string parameter)
- `-Force` as a switch parameter
- `-Mode` with validation set values: "fast", "full"

### Custom Completions

Enhance autocompletion by adding completion metadata:

```powershell
@{
    "deploy" = @{
        exec = { param([string]$Environment) }
        completions = @{
            Environment = @("dev", "staging", "prod")
        }
        description = "Deploy to specified environment"
    }
}
```

## Configuration Management

ConfigMap also provides `qconf` for managing configuration settings:

### Initialize Configuration Map
```powershell
qconf init
```
Creates a `.configuration.map.ps1` file with sample configuration entries.

### Sample Configuration Map
```powershell
@{
    "database" = @{
        get = { return $env:DATABASE_URL }
        set = { param($_context, $value, $key) 
            $env:DATABASE_URL = $value
            Write-Host "Database URL set to: $value"
        }
        options = @{
            "local" = "Server=localhost;Database=MyApp;Trusted_Connection=true;"
            "staging" = "Server=staging-db;Database=MyApp;Uid=app;Pwd=****;"
            "prod" = "Server=prod-db;Database=MyApp;Uid=app;Pwd=****;"
        }
    }
    
    "api" = @{
        get = { return $env:API_ENDPOINT }
        set = { param($_context, $value, $key)
            $env:API_ENDPOINT = $value
        }
        validate = { param($path, $value, $key)
            return $value -match "^https?://"
        }
        options = @{
            "dev" = "https://api-dev.example.com"
            "staging" = "https://api-staging.example.com"
            "prod" = "https://api.example.com"
        }
    }
}
```

### Configuration Usage
```powershell
# Get current values
qconf get -entry database
qconf get -entry api

# Set configuration values
qconf set -entry database -value local
qconf set -entry api -value dev

# Tab completion works for entries and options
qconf set -entry <TAB>           # Shows: database, api
qconf set -entry database -value <TAB>  # Shows: local, staging, prod
```

## Core Functions

### Import-ConfigMap
Loads and validates map files:
```powershell
$buildMap = Import-ConfigMap ".build.map.ps1"
$configMap = Import-ConfigMap ".configuration.map.ps1"
```

### Get-MapEntry / Get-MapEntries
Retrieves specific entries:
```powershell
$entry = Get-MapEntry $buildMap "build"
$entries = Get-MapEntries $buildMap @("build", "test")
```

### Invoke-EntryCommand
Executes commands defined in map entries:
```powershell
Invoke-EntryCommand $entry "exec" -bound $parameters
```

### Get-CompletionList
Extracts available entries for tab completion:
```powershell
$entries = Get-CompletionList $buildMap -flatten
```

## Entry Types

### Script Blocks
Direct PowerShell execution:
```powershell
"mytask" = { Write-Host "Hello World" }
```

### Command Objects
Structured entries with multiple properties:
```powershell
"mytask" = @{
    exec = { Write-Host "Executing..." }
    description = "My custom task"
    validate = { param($path, $value, $key) return $true }
}
```

### Nested Lists
Hierarchical command organization:
```powershell
"category" = @{
    list = @{
        "item1" = { Write-Host "Item 1" }
        "item2" = { Write-Host "Item 2" }
    }
}
```

## Requirements

- PowerShell 7.0 or higher
- publishmap module (automatically loaded)

## Error Handling

ConfigMap provides detailed error messages for:
- Missing map files
- Invalid entry names  
- Missing commands in entries
- Parameter validation errors
- Type validation errors

## Reserved Keys

The following keys have special meaning in map files:
- `exec` - Default execution command
- `list` - Nested entry container
- `options` - Configuration options list (for qconf)
- `get` - Get configuration value (for qconf)
- `set` - Set configuration value (for qconf)
- `validate` - Validation function (for qconf)
- `description` - Command description
- `completions` - Custom tab completion values

## Examples

### Simple Build Workflow
```powershell
# .build.map.ps1
@{
    "clean" = { Remove-Item bin,obj -Recurse -Force -ErrorAction Ignore }
    "restore" = { dotnet restore }
    "build" = { dotnet build --no-restore }
    "test" = { dotnet test --no-build }
    "package" = { dotnet pack --no-build }
}
```

Usage:
```powershell
qbuild clean
qbuild restore  
qbuild build
qbuild test
qbuild package
```

### Multi-Stage Build with Parameters
```powershell
@{
    "build" = @{
        exec = {
            param(
                [ValidateSet("Debug", "Release")]$Configuration = "Debug",
                [switch]$NoRestore
            )
            $args = @("build", "--configuration", $Configuration)
            if ($NoRestore) { $args += "--no-restore" }
            & dotnet @args
        }
    }
}
```

Usage:
```powershell
qbuild build -Configuration Release -NoRestore
```

## Module Structure

- **configmap.ps1** - Main module implementation
- **configmap.psm1** - Module manifest and function exports
- **samples/_default/** - Template files for `init` commands

## Testing

Run the test suite:
```powershell
Invoke-Pester .\configmap.tests.ps1
```