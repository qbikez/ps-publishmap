# AGENTS.md

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
- PowerShell aliases permitted by `PSScriptAnalyzerSettings.psd1` are acceptable; do not replace them solely for style
- CI/CD via AppVeyor with automatic testing and deployment

### PowerShell Coding Guidelines

#### Scope and Refactoring
- Apply these guidelines to new and changed code
- Make only the changes needed for the requested behavior; propose broader cleanup separately
- Preserve all observable behavior unless the task explicitly authorizes a breaking change. This includes exported commands, aliases, parameters, output, dynamic parameters, completion, and map contracts

#### Functions and Complexity
- Give each function one responsibility and keep its statements at one abstraction level
- Treat roughly 50 executable lines or nesting deeper than three levels as a signal to review the function, not as a hard limit
- Long orchestration functions are acceptable when their steps remain cohesive and readable
- Keep pipeline output deliberate. Do not emit incidental values from method calls or helper commands
- Use `$null -eq $value` where placing a collection on the left could change null-comparison behavior
- Validate public inputs and add types when they clarify or enforce a boundary; avoid types that only add noise internally
- Use `try`/`finally` whenever temporarily changing locations, environment variables, module state, settings scopes, or other process state
- Prefer guard clauses, named arguments, and splatting when they improve readability; they are not mandatory

#### Naming
- Name functions with an approved PowerShell `Verb-SingularNoun` pair, using verbs according to their standard semantics
- Use intention-revealing domain names and otherwise follow the established casing in the surrounding file
- Preserve externally visible names and schema keys such as `exec`, `_settings`, and `_context`

#### Module Organization
- Keep module entry points focused on dependency-ordered imports, exports, and initialization
- Group functions by one cohesive domain concern in the existing `functions/` directories
- Split a file when it accumulates unrelated responsibilities; do not require one file per function

#### Clean Code and Abstractions
- Remove dead and commented-out code; version control retains history
- Comments should explain rationale, constraints, or non-obvious PowerShell behavior rather than restating the code
- Use `Write-Verbose` and `Write-Debug` for diagnostics. Use `Write-Host` only for intentional CLI presentation
- Use terminating errors for operations that cannot produce a valid result
- Extract a helper when it materially improves readability or represents a domain concept or side-effect boundary
- Avoid forwarding wrappers, speculative abstraction layers, and classes that do not improve the existing function/hashtable design
- Prefer pure transformations for business rules and keep side effects near orchestration boundaries where practical

#### Tests
- Use test-driven development for behavior changes and bug fixes, following the red-green-refactor cycle:
  1. **Red:** write a focused test for the desired behavior and confirm that it fails for the expected reason
  2. **Green:** make the smallest production-code change that makes the test pass
  3. **Refactor:** improve the implementation and tests while keeping the suite green
- Do not skip confirming the red phase; a test that never failed may not exercise the intended behavior
- Add a Pester regression test for every bug fix and behavior tests for new features
- Prefer tests through public behavior. Test internal helpers directly when they contain substantial standalone logic
- Mock external boundaries rather than the code under test
- Use `TestDrive` for filesystem tests and reliably restore environment, module, global, and location state
- Run directly related Pester tests before handoff. Run broader suites or PSScriptAnalyzer when requested
- State what verification was and was not run, and report any failures

#### Formatting
- Use consistent indentation and a readable layout
- Follow the nearby style and avoid formatting-only churn

## File Patterns

- Configuration files: `*.config.ps1` (publishmap configurations)
- Module manifests: `*.psd1` 
- Module files: `*.psm1`
- Test files: `*.Tests.ps1` or `*.tests.ps1`
- Function files: Concern-focused `.ps1` files in `/functions/` directories