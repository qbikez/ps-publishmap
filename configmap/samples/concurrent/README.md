# Tmux Integration Sample

This example shows how `qbuild` delegates commands to dedicated tmux windows when you run it from inside a tmux session.

## Prerequisites

- [tmux](https://github.com/tmux/tmux/wiki) installed and on your `PATH`
- ConfigMap module imported (`Import-Module` path to `configmap.psm1`)

## Quick Start

```powershell
# From the configmap module root
Import-Module .\configmap.psm1

# Start tmux and open a shell in this sample directory
cd .\samples\tmux
tmux new-session -s dev
```

Inside the tmux session:

```powershell
Import-Module ..\..\configmap.psm1

# List available entries
qbuild list

# Dispatch to dedicated windows (created automatically if missing)
qbuild build.ui
qbuild build.api -Configuration Release
qbuild test.unit -Watch

# Run all children of a parent entry (each in its own window)
qbuild build.all
qbuild test.all
```

## How It Works

When you invoke `qbuild <entry>` from inside tmux:

1. **Not in tmux** — the entry runs in the current shell (normal behavior).
2. **In tmux, already in window `<entry>`** — the entry runs locally in that window.
3. **In tmux, in a different window** — `qbuild` sends the command to a window named after the full entry path in the **current session**. The target window first `cd`s to the absolute directory where you invoked `qbuild`, then runs the command there.

```
Current tmux session: dev
Current window:       shell

  qbuild build.ui
       │
       ▼
  tmux window "build.ui"  ← created if it does not exist
       │
       ▼
  qbuild build.ui         ← runs there; arguments are preserved
```

Window names match the entry path exactly:

| Command | Tmux window |
|---------|-------------|
| `qbuild build.ui` | `build.ui` |
| `qbuild build.api` | `build.api` |
| `qbuild test.unit` | `test.unit` |
| `qbuild dev.ui` | `dev.ui` |
| `qbuild build.all` | `build.ui`, `build.api` (one window each) |

If the session does not exist, it is created. If the session exists but the window does not, a new window is added.

## Usage Examples

### Run parallel builds from one control window

```powershell
# Stay in your "shell" window and kick off work in separate windows
qbuild build.ui
qbuild build.api
qbuild test.unit
```

Switch between windows with `Ctrl+b` then window number, or:

```powershell
tmux select-window -t dev:build.ui
tmux select-window -t dev:build.api
```

### Arguments are forwarded

Switches and values passed to `qbuild` are included in the command sent to the target window:

```powershell
qbuild build.api -Configuration Release
# → tmux window receives: qbuild -map '...' build.api -Configuration Release

qbuild test.unit -- --filter MyTest
# → passthrough args after -- are preserved
```

### Re-run in the same window

Once you are attached to `build.ui` and run `qbuild build.ui` again, it executes locally — no re-dispatch loop.

```powershell
tmux select-window -t dev:build.ui
qbuild build.ui -Configuration Debug   # runs here directly
```

## Sample Entries

This map defines a small multi-service project layout:

```powershell
qbuild build.ui              # frontend build
qbuild build.api             # backend build
qbuild test.unit -Watch      # unit tests
qbuild test.integration      # integration tests
qbuild dev.ui                # simulated UI dev server
qbuild dev.api               # simulated API dev server
```

Commands use `Start-Sleep` to simulate work so you can watch output appear in each tmux window.

## Notes

- Tmux auto-window delegation is **enabled by default**. Set `$env:QCONF_TMUX_AUTOWINDOW` to a falsy value (`0`, `false`, `no`, or `off`) to run entries locally even inside tmux.
- When inside tmux, tmux takes precedence over the concurrently plugin for virtual `.all` expansions (e.g. `build.all`). Outside tmux, `build.all` runs via `npx concurrently` when that plugin is enabled.
- Delegation requires a **file-based** map (`-map` path or default `.build.map.ps1`). In-memory hashtable maps always run locally.
- `help`, `list`, and `!init` are not delegated — they always run in the current shell.
- Parent entries without `exec` (e.g. `qbuild build`) still show the subcommand chooser locally.

## See Also

- `samples/hierarchical/` — organizing entries with dot notation
- `test/qbuild.tests.ps1` — automated tests for tmux delegation (`Describe "qbuild tmux"`)
