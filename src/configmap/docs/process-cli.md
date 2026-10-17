# Process CLI

qbuild process types (`_settings.process`) are **`exec`** (default), **`steps`**, and **`options`**.
Legacy map values `qrun` and `qconf` still normalize to `steps` and `options`.

Standalone CLI aliases remain **`qrun`** (steps runner) and **`qconf`** (options/config).
They expose a small CLI surface that in-process handlers call with the PowerShell
call operator (`&`). Flags are single-dash only.

Map handoff is **path-only**: callers pass `-map <file>`. The process command loads that file itself.

## Shared surface

```text
qrun [-map <path>] [-entry <entry>] [opaque-args...]
qrun [-map <path>] list [<entry>]
qrun [-map <path>] !complete -word <prefix> [-entry <entry>]
qrun [-map <path>] !complete -params -entry <entry>

qconf [-map <path>] <entry> get
qconf [-map <path>] <entry> set <option-key>
qconf [-map <path>] <entry> show
qconf [-map <path>] [-entry <entry>] [-value <option-key>] [opaque-args...]
qconf [-map <path>] list [<entry>]
qconf [-map <path>] !complete -word <prefix> [-entry <entry>]
qconf [-map <path>] !complete -params -entry <entry>
```

| Form | Behavior |
|------|----------|
| `-map` | Path to the map file (default `.process.map.ps1`) |
| `-entry <entry>` | Run target (also accepts positional `qrun <entry>` for direct use) |
| `list` | List processes; `list <entry>` prints that entry’s status tree |
| `!complete -word` | One completion candidate per stdout line; exit `2` if unsupported |
| `!complete -params` | One parameter name per line (no leading `-`); exit `2` if unsupported |

Success is exit `0` / no throw. Failure is non-zero exit or a terminating error.

For qconf, `get` reads the entry and `set <option-key>` applies a named option.
`show` prints the same host-formatted status block used by `list <entry>`.
A bare entry still performs a get, and `-value <option-key>` remains a set
shorthand. qbuild forwards these as opaque, process-owned arguments.

## Map declaration

```powershell
# Step runner (CLI: qrun)
_settings = @{ process = 'steps' }

# Config get/set (CLI: qconf)
_settings = @{ process = 'options' }

# Still accepted (normalized to steps / options)
_settings = @{ process = 'qrun' }
_settings = @{ process = 'qconf' }
```

## Process-owned (not part of the shared handoff)

These stay on the process command for direct use:

```text
qrun help
qrun !state [show|clean] [<entry>]
qrun <entry> [-Follow] [-Force] [-Status] [-Reset] …
```

Callers that only use the shared surface should not special-case these switches; they discover names via `!complete -params` and forward whatever the user bound.
