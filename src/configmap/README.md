# ConfigMap

ConfigMap is a PowerShell module that extends publishmap functionality to provide build and configuration management capabilities through declarative map files.

## Requirements

- PowerShell 7.0 or higher

## Overview

ConfigMap provides a framework for managing build scripts and configuration settings using nested hashtables. It offers three main command-line tools:

- **qbuild** - Build script management
- **qconf** - Configuration management  

## Quick Start

### Initialize a Build Map

```powershell
qbuild init
```

This creates a `.build.map.ps1` file with sample build scripts.

### Initialize a Configuration Map

```powershell
qconf init
```

This creates a `.configuration.map.ps1` file with sample configuration entries.

### Run Build Scripts

```powershell
# List available build scripts
qbuild help

# Run a specific build script
qbuild mybuildscript

# Run with parameters (if script supports them)
qbuild mybuildscript -param1 value1
```

### Manage Configuration

```powershell
# Get current configuration values
qconf get -entry mymodule

# Set configuration values
qconf set -entry mymodule -value myoption
```

## Map File Structure

### Build Maps (`.build.map.ps1`)

Build maps define executable scripts organized in a nested structure:

```powershell
@{
    "build" = @{
        exec = { 
            Write-Host "Building project..."
            # Build logic here
        }
    }
    "test" = @{
        exec = {
            Write-Host "Running tests..."
            # Test logic here  
        }
    }
    "deploy" = @{
        list = @{
            "staging" = { Write-Host "Deploying to staging..." }
            "production" = { Write-Host "Deploying to production..." }
        }
    }
}
```

### Configuration Maps (`.configuration.map.ps1`)

Configuration maps define settings with available options:

```powershell
@{
    "database" = @{
        get = { param($context, $options) 
            # Return current database setting
        }
        set = { param($context, $value, $key)
            # Set database configuration
        }
        options = @{
            "local" = "localhost:5432"
            "staging" = "staging-db:5432" 
            "production" = "prod-db:5432"
        }
    }
}
```

## Core Functions

### Import-ConfigMap
Loads and validates map files from disk or objects.

```powershell
$map = Import-ConfigMap "my-config.ps1"
```

### Get-CompletionList
Extracts available entries from maps for tab completion.

```powershell
$entries = Get-CompletionList $map -flatten
```

### Get-MapEntry / Get-MapEntries
Retrieves specific entries from loaded maps.

```powershell
$entry = Get-MapEntry $map "mykey"
$entries = Get-MapEntries $map @("key1", "key2")
```

### Invoke-EntryCommand
Executes commands defined in map entries.

```powershell
Invoke-EntryCommand $entry "exec" -bound $parameters
```

## Entry Types

### Script Blocks
Direct PowerShell script execution:

```powershell
"mytask" = { Write-Host "Hello World" }
```

### Command Objects
Objects with multiple commands:

```powershell
"mytask" = @{
    exec = { Write-Host "Executing..." }
    validate = { param($path, $value, $key) return $true }
}
```

### Nested Lists
Hierarchical organization:

```powershell
"category" = @{
    list = @{
        "item1" = { Write-Host "Item 1" }
        "item2" = { Write-Host "Item 2" }
    }
}
```

## Dynamic Parameters

Both qbuild and qconf support dynamic parameters based on the target script's parameter block:

```powershell
# If your build script has parameters:
"mybuild" = @{
    exec = { 
        param([string]$Environment, [switch]$Force)
        Write-Host "Building for $Environment"
    }
}

# You can call it with those parameters:
qbuild mybuild -Environment "staging" -Force
```

## Tab Completion

All commands provide rich tab completion for:
- Available entries/scripts
- Configuration options
- Dynamic parameters

## Error Handling

The module provides detailed error messages for common issues:
- Missing map files
- Invalid entry names
- Missing commands in entries
- Type validation errors

## Reserved Keys

The following keys are reserved and have special meaning:
- `options` - Configuration options list
- `exec` - Default execution command
- `list` - Nested entry container

## Examples

### Simple Build Script

```powershell
# .build.map.ps1
@{
    "clean" = { Remove-Item "bin", "obj" -Recurse -Force -ErrorAction SilentlyContinue }
    "build" = { dotnet build --configuration Release }
    "test" = { dotnet test --no-build }
}
```

Usage:
```powershell
qbuild clean
qbuild build
qbuild test
```

### Configuration with Validation

```powershell
# .configuration.map.ps1
@{
    "api" = @{
        get = { return $env:API_ENDPOINT }
        set = { param($context, $value, $key) 
            $env:API_ENDPOINT = $value
            Write-Host "API endpoint set to: $value"
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

Usage:
```powershell
qconf get -entry api
qconf set -entry api -value dev
```

## Module Structure

- **configmap.ps1** - Main module file with all functions
- **configmap.psm1** - Module manifest and exports
- **samples/_default/** - Template files for initialization

## Testing

Run the test suite:
```powershell
Invoke-Pester .\configmap.tests.ps1
```