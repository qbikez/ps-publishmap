# PublishMap

PublishMap processes hierarchical PowerShell hashtables into reusable deployment and configuration profiles. It supports property inheritance, global profiles, and variable substitution.

## Getting started

Import the module and load a map file:

```powershell
Import-Module .\publishmap.psm1

$map = Import-PublishMap .\mymap.config.ps1
$profile = Get-Profile 'qlogger.viewer.dev' $map
```

## Map structure

A publish map has three levels: group, project, and profile. Project properties are inherited by their profiles.

```powershell
@{
    qlogger = @{
        viewer = @{
            sln = 'Qlogger.sln'
            proj = 'src\Qlogger.Viewer.Web\Qlogger.Viewer.Web.csproj'
            profiles = @{
                dev = @{
                    Configuration = 'Debug'
                    ComputerName = 'dev-server'
                }
                prod = @{
                    Configuration = 'Release'
                    ComputerName = 'prod-server'
                }
            }
        }
    }
}
```

Use `global_profiles` in a group to define profiles inherited by every project in that group:

```powershell
@{
    qlogger = @{
        global_profiles = @{
            dev = @{
                Configuration = 'Debug'
                ComputerName = 'dev-server'
            }
        }
        viewer = @{
            profiles = @{
                dev = @{
                    appname = '/viewer'
                }
            }
        }
    }
}
```

## Commands

- `Import-PublishMap` / `Import-Map` — load and process a map file.
- `Get-Profile` / `Get-Entry` — retrieve an entry by its dot-separated map path.
- `Convert-Vars` — expand variables in map values.
- `Add-InheritedProperties` — copy inherited properties between map entries.

Processed profiles include `_name`, `_level`, and `_fullpath` metadata, and have access to inherited project and global-profile properties.
