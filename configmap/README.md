# ConfigMap

ConfigMap is a PowerShell module that turns a declarative map file (`.build.map.ps1`) into a CLI. Each map entry becomes a `qbuild` command with tab completion, parameters, help and structured discovery.

```powershell
# .build.map.ps1
@{
    clean = { Remove-Item bin, obj -Recurse -Force -ErrorAction Ignore }
    build = @{
        description = 'Build the project'
        exec        = {
            param([ValidateSet('Debug', 'Release')]$Configuration = 'Debug')
            dotnet build --configuration $Configuration
        }
    }
}
```

```powershell
qbuild                              # list commands
qbuild build -Configuration Release # run one, with completed parameters
```

## Installation

Requires PowerShell 7.0 or later.

```powershell
Install-Module configmap -Scope CurrentUser
Import-Module configmap   # add to your $PROFILE to get qbuild and its completion everywhere
```

To use a local checkout instead, import `configmap/configmap.psm1`.

Optional extras:

```powershell
qbuild !extension.install          # VS Code / Cursor extension for map files (see vscode-qbuild/)
qbuild !agent.init -Agent claude   # install agent skills (cursor, claude, copilot)
```

## Getting started

```powershell
qbuild !init           # create .build.map.ps1 with defaults detected for this directory
qbuild !init.options   # add the defaults for one process type: exec, options, steps, bun, npm
qbuild help
```

## Features

### Commands from map entries

An entry is a scriptblock or a hashtable with `exec` and `description`. Nested hashtables group commands and are addressed with dot notation.

```powershell
@{
    frontend = @{
        build = { npm run build }
        test  = @{ exec = { param([switch]$Watch) npm test }; description = 'Run UI tests' }
    }
}
```

```powershell
qbuild frontend.test -Watch
qbuild frontend.all      # run every child of the group
```

### Tab completion and parameters

Entry names, parameter names and `ValidateSet` values complete automatically from each scriptblock's `param()` block. A `ValidateSet('@key')` takes its values from a sibling key, which can be a scriptblock evaluated lazily:

```powershell
deploy = @{
    envs = { Get-EnvNames }
    exec = { param([ValidateSet('@envs')][string]$Env) ... }
}
```

### Process types

`_settings.process` chooses how an entry runs:

| Process | Behavior |
|---------|----------|
| `exec` (default) | Run the entry's `exec` scriptblock |
| `steps` | Multi-step process with persisted state, `-Check`, `-Force`, `-Reset` |
| `options` | Configuration values with get / set / show |
| `bun`, `npm` | Proxy to `package.json` scripts |

```powershell
@{
    bootstrap = [ordered]@{
        _settings = @{ process = 'steps' }
        prepare   = @{ exec = { ./prepare.ps1 }; check = { Test-Path prepared.txt } }
        install   = { dotnet tool restore }
    }
    web = @{ _settings = @{ process = 'bun' } }
}
```

```powershell
qbuild bootstrap           # runs pending steps only
qbuild bootstrap -Check    # verifies real state instead of trusting the cache
qbuild web dev -- --watch  # bun run dev --watch
```

### Configuration switching

`options` entries switch configuration between named presets. Built-in templates handle common stores, so no `get`/`set` code is needed:

```powershell
@{
    _settings = @{ process = 'options' }
    storage = @{
        _template = 'appsettings:src/appsettings.Development.json'
        options   = @{
            local = @{ 'Storage:BaseUrl' = 'https://127.0.0.1:10000' }
            prod  = @{ 'Storage:BaseUrl' = 'https://prod.example' }
        }
    }
    envfile = @{ _template = 'dotenv:.env' }                     # presets found from .env.* files
    mongo   = @{ _template = 'user-secrets:src/App/App.csproj'; options = @{ local = @{ 'ConnectionStrings:mongo' = '' } } }
    api     = @{
        get     = { $env:API_URL }
        set     = { param($_context, $value) $env:API_URL = $value }
        options = @{ dev = 'https://dev.example'; prod = 'https://api.example' }
    }
}
```

```powershell
qbuild storage               # show the current value
qbuild storage -value prod   # apply a preset
```

Templates: `appsettings` (JSON), `dotenv`, `user-secrets`. A custom `get`/`set` overrides the template and can call it through `$_context.base`.

### Composing maps

- `#include` merges other map files, optionally prefixed with the child's name.
- `_settings` is inherited from the map and parent entries; `QCONF_<Setting>` environment variables override defaults.
- `_settings.useWorkDir` runs scripts in the caller's directory instead of the map's.

```powershell
@{
    '#include' = @{ child = @{ prefix = $true } }   # child/.build.map.ps1 -> qbuild child.<entry>
}
```

### Plugins

- **concurrently** — with `_settings.Concurrently`, `qbuild <group>.all` runs the children in parallel through `npx concurrently`.
- **tmux** — with `_settings.TmuxAutoWindow`, inside tmux each target runs in its own window named after the entry.

### Discovery for agents and scripts

```powershell
qbuild !describe build | ConvertTo-Json -Depth 6   # structured command catalog
qbuild list -Type steps                            # filter by process type
qbuild !settings                                   # effective settings
qbuild !cache.rebuild                              # reset the discovery cache
```

The discovery cache (`.configmap/` next to the map) keeps completion fast and is invalidated when the map, its includes or `_dependsOn` files change. It is safe to delete or gitignore.

The same data is available from PowerShell with `Import-ConfigMap` and `Get-ConfigMapCommandCatalog`.

## Architecture

```
qbuild (host/qbuild.ps1)
  ├─ resolve map        functions/resolve-map.ps1, map-entries.ps1   find, import, #include, discovery cache
  ├─ internal commands  functions/internal-commands.ps1              help, list, !init, !describe, !cache, ...
  ├─ run context        functions/run-context.ps1, settings.ps1      effective _settings per entry
  ├─ plugins            plugins/*                                    hooks that can take over dispatch
  └─ process handlers   handlers/*                                   exec, steps (qrun), options (qconf), bun/npm
```

1. **Map resolution.** `qbuild` finds the nearest `.build.map.ps1`, imports it, merges `#include`d maps and resolves the entry path (`group.entry`).
2. **Settings.** Each run gets a run context. An entry's settings are the defaults plus `QCONF_*` variables, layered with the map's, ancestors' and entry's `_settings`. A nested `qbuild` call starts fresh and does not inherit the caller's settings.
3. **Dispatch.** Plugins get the first chance to handle the targets. Otherwise the process type picks a handler, which owns that entry's parameters, completion and execution.
4. **Completion.** Completers read entry names and `param()` blocks without running entries, backed by the discovery cache.

Each handler registers an `!init.<type>` template (`handlers/<type>/init.map.ps1`) used by `qbuild !init`.

`qrun` and `qconf` remain as deprecated standalone CLIs for the `steps` and `options` processes; see [docs/process-cli.md](docs/process-cli.md).

## Samples

`samples/` contains runnable maps: `hierarchical`, `include`, `qrun` (steps), `process-mixed`, `dotenv`, `pkg`, `concurrent`, `playwright`, `dir-context`.

## Development

```powershell
Invoke-Pester ./test                          # tests
./test/Measure-ConfigMapPerformance.ps1      # optional performance benchmark
```
