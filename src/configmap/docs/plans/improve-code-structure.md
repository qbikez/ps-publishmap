# Improve configmap structure

Three structural changes, in impact order. Behavior listed under each item stays the same.

## 1. One dotted import for map files

### Why it matters

`Resolve-ConfigMap` only finds the file. Every caller then repeats the same pipeline: if the source is a file, dot-source it and pipe it through `Add-BaseDir`.

That block is copied in:

- `src/functions/qbuild.ps1` — argument completer, `dynamicparam`, `list`, and `process` inside `Invoke-QBuild`
- `src/functions/qconf.ps1` — both completers, `dynamicparam`, and `process` inside `Invoke-QConf`

`src/functions/resolve-map.ps1` documents the copy in a comment, because a normal function would hide map-file imports from the caller. The copies have already drifted: `qconf` sometimes omits `-fallback`, and its `process` block special-cases a hashtable map that the other sites do not.

Any change to loading (includes, `_baseDir`, object maps, error handling) has to be edited in all eight sites, and tests repeat the same pipeline.

### Change

Add one scriptblock next to `Resolve-ConfigMap` in `src/functions/resolve-map.ps1`. Dot-source it at each call site:

```powershell
. $ImportConfigMap -Map $map -Fallback './.build.map.ps1'
```

Dot-sourcing keeps the map file's own dot-sources in the caller's scope. Each of the eight sites becomes that one call, plus the error handling it already has (`-ErrorAction`, missing file, `Assert-ConfigMap`).

### What stays

Fallback paths, parent-directory lookup, object maps, `_baseDir` injection, and imports defined inside a map file remain visible to the caller.

## 2. One settings scope per command

### Why it matters

A single `qbuild` entry pushes `$script:ConfigMapSettings` three times:

1. `Invoke-QBuild` enters the map's `_settings`.
2. `Enter-ConfigMapAncestorSettingsScopes` in `src/functions/settings.ps1` walks `.`-separated keys (and `list`).
3. `Invoke-EntryWrapper` and `Invoke-EntryCommand` in `src/functions/invoke-entry.ps1` each enter the leaf's `_settings` again.

Each `try`/`finally` must exit in order. A missed exit leaves the session on the entry's settings.

`qconf` only enters the map scope, so a nested configuration entry never sees its parents' `_settings`. The ancestor walk also uses different path rules than `Get-MapEntries` (no `#include` prefixes), so included build entries do not pick up parent settings.

### Change

Add one helper in `src/functions/settings.ps1`:

```powershell
Invoke-WithEntrySettings -Map $map -EntryKey $key -Entry $entry -ScriptBlock { ... }
```

It pushes map, ancestor, and leaf settings once and always pops them.

- Call it from `Invoke-QBuild` around the plugin hook and around each target.
- Call it from `Invoke-QConf` around `get` and `set`.
- Remove the scope enter/exit from `Invoke-EntryWrapper` and `Invoke-EntryCommand`.

### What stays

Environment defaults, unknown-setting errors, `Test-ConfigMapFeatureEnabled`, and the settings values plugins and entry scripts see stay the same. Applying the same `_settings` hashtable twice is already an overwrite, so dropping the extra push does not change those values.

## 3. Resolve entries without going through the completer

### Why it matters

`Get-MapEntries` in `src/functions/map-entries.ps1` finds a command by building the full completion list and filtering it. `entry.all` runs only because `Get-CompletionList` in `src/functions/completion.ps1` inserts a fake `__buildAll` node.

Help, tab completion, and dispatch therefore share one walker. A change to flatten, separator, or group marker changes which script `qbuild` runs.

The same walker is also the third definition of "this key is metadata":

- `Get-MapLanguage` in `src/functions/languages.ps1`
- the hardcoded list in `Add-BaseDir` (`src/functions/resolve-map.ps1`)
- the default parameter on `Test-IsParentEntry` (`src/functions/map-entries.ps1`)

Each list names different keys. `_settings` is a hashtable. If it is missing from the list used by `Test-IsParentEntry`, that entry becomes a parent command.

### Change

Move the tree walk (includes, parent versus leaf, skip metadata keys) into something `Get-MapEntries` owns, and have it expand `.all` there via the existing `Get-BuildAllChildren`.

Leave `Get-CompletionList` and `Get-EntryCompletion` as the formatting step over that walk for tab completion and `Write-MapHelp`.

Point `Add-BaseDir` and `Test-IsParentEntry` at `Get-MapLanguage` instead of their own key lists. Add the keys those lists already care about (`description`, `validate`) to `src/functions/languages.ps1`.

### What stays

Tab completion names, `qbuild entry.all`, `#include` merging, and which keys are runnable commands stay the same.
