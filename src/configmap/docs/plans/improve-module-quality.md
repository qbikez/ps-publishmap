# Improve ConfigMap module quality

## Goal

Improve readability, simplicity, and maintainability by consolidating map
traversal, standardizing map loading, and defining a deliberate public API.
The changes should preserve existing `qbuild`, `qconf`, include, settings, and
tab-completion behavior.

## Current state

The earlier structural work is partly complete:

- `$ImportConfigMap` in `src/functions/resolve-map.ps1` centralizes top-level
  map imports.
- `Invoke-WithEntrySettings` in `src/functions/settings.ps1` centralizes
  settings scope lifetime.

The remaining complexity is in independently implemented map traversal and
include loading, plus an ambiguous public module surface.

## 1. Use one canonical entry-discovery pipeline

### Problem

Map discovery is implemented independently for execution, help/list output,
and completion:

- `Get-MapEntryList` and `Merge-IncludeDirectives` in
  `src/functions/completion.ps1`
- `Add-EntryCompletionCandidates` in `src/functions/completion.ps1`
- `Resolve-MapEntrySegments` and `Get-MapEntries` in
  `src/functions/map-entries.ps1`

Each path must interpret nested `list` structures, `#include`, language
reserved keys, parent entries, and build-specific `.all` commands. A change to
one walker can cause completion, help, and execution to disagree.

### Change

Create one internal traversal function, such as `Get-ConfigMapEntries`, that
returns normalized descriptors:

```powershell
[pscustomobject]@{
    Key       = 'deploy.api'
    Entry     = $entry
    IsParent  = $false
    SourceMap = $map
}
```

Make the existing consumers use this traversal:

- `Get-MapEntries` performs exact lookup and expands `<parent>.all` targets.
- `Get-EntryCompletion` filters and sorts discovered keys.
- `Get-CompletionList` exposes the same entries as an ordered map for
  compatibility.
- `Write-MapHelp` formats descriptions and parameters without walking maps.

Keep each consumer responsible only for its output format, not for map
interpretation.

### Acceptance criteria

- A shared fixture produces the same command names for `Get-MapEntries`,
  `Get-CompletionList`, and `Get-EntryCompletion`.
- Nested `list` entries, `#include` directives with and without prefixes,
  metadata keys, and `<parent>.all` work as before.
- Existing public return shapes remain compatible.

### Tests

Add table-driven Pester coverage for normalized discovery and compatibility
tests for execution, help/list, and completion over the same fixtures.

## 2. Consolidate root and included-map loading

### Problem

Loading behavior is split across several functions:

- `$ImportConfigMap` in `src/functions/resolve-map.ps1`
- `Import-IncludedConfigMap` in `src/functions/settings.ps1`
- `Merge-IncludeDirectives` and `Get-CompletionIncludedMap` in
  `src/functions/completion.ps1`

These paths differ in caching, cycle detection, error reporting, and
`_baseDir` injection. `Resolve-ConfigMapFile` also declares `$mapFile` but
uses dynamically scoped `$map` and `$lookUp`, which is fragile and obscures
the function contract.

### Change

Introduce an internal loader with explicit inputs:

```powershell
Import-ConfigMapSource `
    -Map $map `
    -Fallback $fallback `
    -LookUp:$lookUp `
    -BaseDirectory $baseDirectory `
    -OperationContext $operationContext
```

Return a consistent source object:

```powershell
[pscustomobject]@{
    Map        = $map
    SourceFile = $resolvedPath
    BaseDir    = $baseDir
}
```

Use this loader for both root maps and `#include` maps. Keep the operation
context responsible for include caching and cycle detection. Define one
explicit missing-map contract, rather than mixing `$null`, warnings, and
exceptions.

Update `Resolve-ConfigMapFile` to use only declared parameter names and add
`LookUp` as an explicit parameter when needed.

### Acceptance criteria

- Primary map and included-map loading apply the same validation and base
  directory rules.
- A map is loaded once per operation context when referenced repeatedly.
- Include cycles terminate safely and predictably.
- Missing root maps and missing included maps produce intentional,
  documented behavior.

### Tests

Add Pester coverage for direct resolution with and without parent lookup,
included-map caching, include cycles, missing include directories, missing map
files, and `_baseDir` propagation.

## 3. Define and enforce the public module API

### Problem

The public surface is inconsistent:

- `configmap.psm1` explicitly exports a large list of functions.
- `configmap.psd1` uses `FunctionsToExport = @('*')`, which may expose new
  implementation helpers by accident.
- `README.md` documents `Import-ConfigMap`, while the implementation currently
  exposes `$ImportConfigMap` as a variable/script block instead of a public
  command.

This makes it difficult to distinguish supported APIs from internal helpers
and makes refactoring unnecessarily risky.

### Change

1. Define the supported commands and advanced APIs.
2. Add a public `Import-ConfigMap` function backed by the internal loader.
3. Replace the manifest wildcard with the exact supported function names.
4. Keep traversal, loading, and completion implementation helpers private.
5. Update `README.md` so documented commands exactly match the manifest.

The expected public surface should include `qbuild`, `qconf`, and selected
inspection/import functions such as `Import-ConfigMap`, `Get-MapEntry`, and
`Get-MapEntries`. Decide whether `Invoke-EntryCommand` is intentionally
supported before exporting it.

### Acceptance criteria

- `Get-Command -Module ConfigMap` matches the manifest's explicit exports.
- `Import-ConfigMap` is a real command and successfully imports a temporary
  build and configuration map.
- The README's documented core functions are importable after
  `Import-Module`.
- Internal helpers cannot become public accidentally.

### Tests

Add a Pester public-API contract test that compares the module's exported
commands and aliases to an expected list. Add smoke tests for the documented
`Import-ConfigMap` examples.

## Implementation order

1. Implement and test the unified loader first, because traversal needs a
   stable source-loading contract.
2. Replace duplicate entry walkers with the canonical discovery pipeline while
   retaining compatibility adapters for existing public functions.
3. Define explicit exports, introduce the public import command, and update
   documentation and API contract tests.
4. Run the focused ConfigMap Pester tests, then the repository test suite if
   the focused tests pass.

## Compatibility constraints

- Preserve map-file dot-sourcing visibility for map-authored helpers.
- Preserve parent-directory fallback and child-named map lookup behavior.
- Preserve `_baseDir`, operation-context caching, and settings scoping.
- Preserve existing command names, aliases, map syntax, completion names, and
  `.all` behavior unless a separately approved breaking-change plan says
  otherwise.
