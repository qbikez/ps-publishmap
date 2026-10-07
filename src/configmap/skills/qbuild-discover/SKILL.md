---
name: qbuild-discover
description: >-
  Discovers, runs, and edits project build commands via qbuild and per-project
  .build.map.ps1 files. Use when building, testing, cleaning, deploying,
  listing or changing project scripts, working in a multi-project workspace,
  or when the user mentions qbuild, configmap, or a .build.map.ps1 file.
---

# qbuild discovery

Each project owns a `.build.map.ps1` in its root. `qbuild` resolves that file from the **current working directory** (then parents). Wrong cwd ⇒ wrong or missing map.

## Locate the project map

1. Identify the target project (path the user named, open file, or repo subfolder).
2. Find that project's map:
   - Prefer `<project>/.build.map.ps1`
   - Else walk parents from that project dir only
3. **`cd` into the project directory** (the folder that contains / owns the map) before any `qbuild` call. Do not run `qbuild` from a workspace root that has a different project's map higher up.
4. If several projects have maps, never assume the cwd map is the right one — resolve from the project you were asked about.
5. If no map exists for that project, tell the user. Do not run `qbuild !init` unless they ask to create one.

## Playbook (run / inspect)

From the project directory:

1. Discover commands:

   ```powershell
   qbuild !describe
   # or for non-PowerShell tooling:
   qbuild !describe | ConvertTo-Json -Depth 6
   ```

   Never invent entry names. Only use names returned by `!describe`.

2. Run only catalogued commands with their documented parameters. Prefer each entry's `Description`, `ValidateSet`, and `DefaultValue`.
3. For concurrency/tmux/debug settings, use `qbuild !settings` or `qbuild !settings <path>` — do not guess `_settings` keys.
4. Prefer the catalog over reading the whole map file when **running** commands.

## Edit scripts

Entry script bodies live in the project's map (or maps it `#include`s):

1. Open `<project>/.build.map.ps1` (follow `#include` / nested maps if the entry is not there).
2. Edit the named entry's `exec` scriptblock (or the entry if it is a bare scriptblock).
3. After edits, re-check with `qbuild !describe <name>` from that project directory.
4. Do not invent new top-level entries without user intent; match existing map style (hashtable + `exec` / `description` vs bare scriptblock).

## Command cheat sheet

| Goal | Command |
|------|---------|
| Install this skill | `qbuild !agent.init [-Scope project\|user] [-Agent cursor\|claude\|copilot]` |
| Full catalog (objects) | `qbuild !describe` |
| One command | `qbuild !describe <name>` |
| Human listing | `qbuild` or `qbuild list` |
| Effective settings | `qbuild !settings [path]` |
| Run a command | `qbuild <name> [-Param value ...]` |

## Catalog shape

Each object has `Name`, `Description`, `IsParent`, and `Parameters` (`Name`, `Type`, `IsSwitch`, `ValidateSet`, `DefaultValue`).
