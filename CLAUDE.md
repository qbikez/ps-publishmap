# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains **publishmap**, a PowerShell module for creating declarative publish configurations using nested hashtables with three levels: group → project → profile. The module processes these maps to enable inheritance and variable substitution for deployment scenarios.

### Core Modules

- **publishmap** (`src/publishmap/`) - Main module for processing publish maps with inheritance and variable substitution
- **configmap** (`src/configmap/`) - Extended module that adds build/configuration management functionality on top of publishmap
- **publishmap.native** (`src/publishmap.native/`) - C# .NET components providing core functionality

## Development Commands

### Build Commands
```powershell
# Build the C# native components
./build.ps1

# Build using npm script
npm run init     # Initialize git submodules and dependencies  
npm run restore  # Restore packages/dependencies
```

### Testing Commands
```powershell
# Run all tests (PowerShell + C# tests)
./test.ps1

# Run tests via npm
npm test

# Run tests via Grunt
grunt test

# Run just C# tests
cd src/publishmap.native/publishmap.test
dotnet test
```

### Other Commands
```powershell
# Push/publish module (runs tests first)
npm run push
grunt push

# Install module locally
npm run install
```

## Architecture

### Module Structure
- **publishmap.psm1** - Main module entry point that exports core functions via `imports.ps1`
- **imports.ps1** - Loads all function files from `/functions/` directory and native C# library
- **functions/** - Individual PowerShell function files (inheritance.ps1, process-map.ps1, etc.)
- **lib/** - Contains compiled C# assemblies copied from publishmap.native during build

### Key Functions (publishmap)
- `Import-PublishMap` / `Import-Map` - Parse and process publishmap configuration files
- `Get-Profile` / `Get-Entry` - Retrieve specific profiles from processed maps
- `Add-InheritedProperties` - Handle property inheritance between levels
- `Convert-Vars` - Variable substitution and expansion

### Key Functions (configmap)  
- `qbuild`, `qconf`, `qrun` - Shorthand commands for build/configure/run operations
- `Get-MapModules` - Discover available map modules
- `Invoke-ModuleCommand` - Execute commands defined in map configurations

### C# Components (publishmap.native)
The native components provide performance-critical functionality:
- **publishmap.core** - Core inheritance and processing logic
- **publishmap.powershell** - PowerShell cmdlet wrappers
- **publishmap.test** - C# unit tests

### Configuration Inheritance
Maps support multi-level inheritance:
1. **Global profiles** - Defined at group level, inherited by all projects
2. **Project properties** - Available to all profiles within a project  
3. **Profile-specific** - Override inherited properties

Example structure:
```
group
├── global_profiles (inherited by all projects)
├── project1
│   ├── project-level properties
│   └── profiles
│       ├── dev (inherits global + project properties)
│       └── prod (inherits global + project properties)
```

## Testing Framework

Uses **Pester** for PowerShell testing. Test files follow the pattern `*.Tests.ps1` or `*.tests.ps1`.

VSCode tasks are configured for running individual test files with Pester integration and proper problem matching.

## Code Quality

- **PSScriptAnalyzer** settings defined in `PSScriptAnalyzerSettings.psd1`
- Allows specific aliases like `cd`, `%`, `select`, `where`, `pushd`, `popd`
- CI/CD via AppVeyor with automatic testing and deployment

## File Patterns

- Configuration files: `*.config.ps1` (publishmap configurations)
- Module manifests: `*.psd1` 
- Module files: `*.psm1`
- Test files: `*.Tests.ps1` or `*.tests.ps1`
- Function files: Individual `.ps1` files in `/functions/` directories