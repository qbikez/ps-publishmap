# Process CLI

`qrun` exposes a small CLI surface that other tools (e.g. future `qbuild` delegation) can call with the PowerShell call operator (`&`). Flags are single-dash only.

Map handoff is **path-only**: callers pass `-map <file>`. The process command loads that file itself.

## Shared surface

```text
qrun [-map <path>] [-entry <entry>] [opaque-args...]
qrun [-map <path>] list [<entry>]
qrun [-map <path>] !complete -word <prefix> [-entry <entry>]
qrun [-map <path>] !complete -params -entry <entry>
```

| Form | Behavior |
|------|----------|
| `-map` | Path to the map file (default `.process.map.ps1`) |
| `-entry <entry>` | Run target (also accepts positional `qrun <entry>` for direct use) |
| `list` | List processes; `list <entry>` prints that entry’s status tree |
| `!complete -word` | One completion candidate per stdout line; exit `2` if unsupported |
| `!complete -params` | One parameter name per line (no leading `-`); exit `2` if unsupported |

Success is exit `0` / no throw. Failure is non-zero exit or a terminating error.

## Process-owned (not part of the shared handoff)

These stay on the process command for direct use:

```text
qrun help
qrun !state [show|clean] [<entry>]
qrun <entry> [-Follow] [-Force] [-Status] [-Reset] …
```

Callers that only use the shared surface should not special-case these switches; they discover names via `!complete -params` and forward whatever the user bound.
