@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'configmap.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.13.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Core')

    # ID used to uniquely identify this module
    GUID = '8b7f4c92-3d1e-4a85-9c6b-f2e8a7d4b1c3'

    # Author of this module
    Author = 'jakub.pawlowski'

    # Company or vendor of this module
    # CompanyName = 'Unknown'

    # Copyright statement for this module
    # Copyright = '(c) 2025 jakub.pawlowski. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'ConfigMap is a PowerShell module that extends publishmap functionality to provide build and configuration management capabilities through declarative map files.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Name of the PowerShell host required by this module
    # PowerShellHostName = ''

    # Minimum version of the PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # DotNetFrameworkVersion = ''

    # Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
    # ClrVersion = ''

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    # RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    # ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    # NestedModules = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        '*'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @('qbuild', 'qconf')

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    # FileList = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('Build', 'Configuration', 'CLI', 'PowerShell', 'ConfigMap', 'PublishMap')

            # A URL to the license for this module.
            # LicenseUri = ''

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/qbikez/ps-publishmap/tree/master/src/configmap'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
## ConfigMap 1.0.0

Initial release of ConfigMap module providing:

### Features
- **qbuild** - Build script management with declarative map files
- **qconf** - Configuration management with validation and options
- Dynamic parameter support for custom script parameters
- Rich tab completion for commands and configuration options
- Professional CLI help formatting
- Inheritance and variable substitution capabilities

### Commands
- `qbuild <script>` - Execute build scripts from .build.map.ps1
- `qconf <command>` - Manage configuration from .configuration.map.ps1
- `qbuild init` - Initialize new build map file
- `qconf init` - Initialize new configuration map file
- `qbuild list` - Show available build scripts with descriptions
- `qbuild help` - Show usage information

### Map File Support
- **.build.map.ps1** - Declarative build script definitions
- **.configuration.map.ps1** - Configuration management with options
- Script blocks with parameter support
- Nested command structures
- Description metadata for documentation

### Requirements
- PowerShell 7.0 or higher
'@

            # Prerelease string of this module
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        } # End of PSData hashtable
    } # End of PrivateData hashtable

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
}





















