# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ConfigMap is a PowerShell module that provides declarative build and configuration management through map files. It offers CLI commands `qbuild` and `qconf` for executing build scripts and managing configurations with rich tab completion and parameter support.

## Development Commands

### Testing Commands
```powershell
# Run all tests using Pester
Invoke-Pester .

# Run specific test file
Invoke-Pester -Path "configmap.tests.ps1"
```

### Module Commands
```powershell
# Import module for testing
Import-Module ./configmap.psm1 -Force

# Test basic functionality
qbuild init      # Creates sample .build.map.ps1
qconf init       # Creates sample .configuration.map.ps1
qbuild list      # Shows available build commands
```

### Sample Usage
```powershell
# Basic build commands
qbuild clean
qbuild build -Configuration Release
qbuild test -Coverage

# Configuration management  
qconf get -entry database
qconf set -entry api -value dev
```

## Architecture

### Core Module Structure
- **configmap.ps1** - Main implementation containing all functions
- **configmap.psm1** - Module manifest that imports and exports functions
- **configmap.psd1** - PowerShell module metadata and dependencies

### Key Functions
- `Import-ConfigMap` - Loads and validates map files (.build.map.ps1, .configuration.map.ps1)
- `Invoke-QBuild` / `qbuild` - Executes build scripts with dynamic parameter discovery
- `Invoke-QConf` / `qconf` - Manages configuration settings with get/set operations
- `Get-CompletionList` - Extracts entries for tab completion support
- `Get-EntryDynamicParam` - Dynamic parameter discovery from script blocks
- `Invoke-EntryCommand` - Executes commands defined in map entries

### Map File Types

#### Build Maps (.build.map.ps1)
Declarative hashtables defining build scripts:
```powershell
@{
    "build" = @{
        exec = { param([string]$Configuration = "Debug") dotnet build --configuration $Configuration }
        description = "Build the project"
    }
    "clean" = { Remove-Item bin,obj -Recurse -Force -ErrorAction Ignore }
}
```

#### Configuration Maps (.configuration.map.ps1)  
Settings management with get/set/validate operations:
```powershell
@{
    "database" = @{
        get = { return $env:DATABASE_URL }
        set = { param($_context, $value, $key) $env:DATABASE_URL = $value }
        options = @{ "local" = "Server=localhost;...", "prod" = "Server=prod;..." }
        validate = { param($path, $value, $key) return $value -match "^Server=" }
    }
}
```

### Dynamic Parameter System
ConfigMap automatically discovers parameters from script blocks using AST parsing:
- Extracts parameter names, types, and attributes from `param()` blocks
- Supports typed parameters, switches, ValidateSet attributes
- Provides tab completion for parameter values
- Special handling for `$_context` parameter (auto-injected, not exposed to CLI)

### Reserved Keys
- `exec` - Default execution command for qbuild
- `get/set/validate` - Configuration operations for qconf  
- `list` - Nested entry container
- `options` - Available configuration values
- `description` - Command documentation

### Sample Files Structure
- `samples/_default/` - Template files for `init` commands
- `samples/build/`, `samples/configure/`, `samples/install/` - Example configurations
- Contains `.build.map.ps1` and `.configuration.map.ps1` templates

## Testing Framework

Uses **Pester** for PowerShell testing:
- `configmap.tests.ps1` - Core functionality tests
- `qbuild.tests.ps1` - Build command integration tests  
- Custom `Should-MatchObject` matcher for hashtable comparison
- Tests cover parameter discovery, command execution, and error handling
- when running tests, report back the status of failed tests

## CLI Features

### Tab Completion
- Command names: `qbuild <TAB>` shows available build scripts
- Parameter names: `qbuild build -<TAB>` shows script parameters
- Parameter values: `qconf set -entry database -value <TAB>` shows options
- Nested entries: Supports hierarchical command structures

### Error Handling
- Missing map files with helpful initialization suggestions
- Invalid entry names with available options
- Parameter validation errors
- Type constraint violations

### Help System
- `qbuild help` / `qconf help` - Usage information
- `qbuild list` - Formatted command listing with descriptions and parameters
- Professional CLI-style help formatting with aligned columns