# CLAUDE.md

Guidance for agents working on the configmap module. See [README.md](README.md) for features and architecture, and the repository [AGENTS.md](../AGENTS.md) for coding guidelines.

## Commands

```powershell
Import-Module ./configmap.psm1 -Force   # load the working copy
Invoke-Pester ./test                    # all tests
Invoke-Pester ./test/<file>.tests.ps1   # one test file
```

When running tests, report the status of any failed tests.

## Where things live

- `host/qbuild.ps1` — the `qbuild` entry point
- `functions/` — map resolution, settings and run context, completion, discovery cache, internal commands
- `handlers/<type>/` — process handlers (`exec`, `qrun` = steps, `qconf` = options, `pkg` = bun/npm) and their `init.map.ps1` templates
- `plugins/` — `concurrently` and `tmux` dispatch hooks
- `samples/` — runnable example maps
- `skills/` — agent skills shipped by `qbuild !agent.init`
- `vscode-qbuild/` — editor extension for map files
