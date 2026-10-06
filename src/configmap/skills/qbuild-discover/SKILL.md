---
name: qbuild-discover
description: >-
  Discovers and runs project build commands via qbuild and .build.map.ps1.
  Use when building, testing, cleaning, deploying, listing project scripts,
  or when the user mentions qbuild, configmap, or a .build.map.ps1 file.
---

# qbuild discovery

## Playbook

1. If `.build.map.ps1` exists in the current directory or a parent, treat `qbuild` as the project's command surface.
2. Discover commands with:

   ```powershell
   qbuild !describe
   # or for non-PowerShell tooling:
   qbuild !describe | ConvertTo-Json -Depth 6
   ```

   Never invent entry names. Only use names returned by `!describe`.

3. Run only catalogued commands with their documented parameters. Prefer each entry's `Description`, `ValidateSet`, and `DefaultValue`.
4. For concurrency/tmux/debug settings, use `qbuild !settings` or `qbuild !settings <path>` — do not guess `_settings` keys.
5. If no map file exists, tell the user. Do not run `qbuild !init` unless the user asks to create a map.
6. Prefer the catalog over reading the whole map file, unless you are implementing or editing the map itself.

## Command cheat sheet

| Goal | Command |
|------|---------|
| Full catalog (objects) | `qbuild !describe` |
| One command | `qbuild !describe <name>` |
| Human listing | `qbuild` or `qbuild list` |
| Effective settings | `qbuild !settings [path]` |
| Run a command | `qbuild <name> [-Param value ...]` |

## Catalog shape

Each object has `Name`, `Description`, `IsParent`, and `Parameters` (`Name`, `Type`, `IsSwitch`, `ValidateSet`, `DefaultValue`).
