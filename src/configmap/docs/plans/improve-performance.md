# Improve ConfigMap performance

This plan targets the time spent loading maps, resolving a selected entry, and
producing tab completions. It keeps the command syntax, command ordering,
include precedence, and dynamic-parameter behavior unchanged.

## Baseline

An in-memory build map with 1,000 simple entries was measured in PowerShell 7
after importing the module:

| Operation | Repetitions | Result |
| --- | ---: | ---: |
| `Get-MapEntries` for one existing entry | 100 | 4,790.6 ms total |
| Single entry lookup | -- | 47.9 ms average |
| `Get-EntryCompletion` for all entries | 10 | 592.6 ms total |
| One completion request | -- | 59.3 ms average |

This is a synthetic baseline. Before changing production code, add equivalent
fixtures that cover real nesting and include patterns. Compare warm-session
median and p95 values, not only an average.

## 1. Resolve explicit entries directly

### Why it matters

`Get-MapEntries` in `src/functions/map-entries.ps1` calls
`Get-MapEntryList`, which walks the complete map, and then filters the
resulting dictionary with `Where-Object` to find one key. Normal `qbuild` and
`qconf` invocations select a single command, so their resolution cost grows
with every unrelated map entry.

`docs/plans/improve-code-structure.md` already proposes separating dispatch
from completion. This item implements that separation with performance
measurements and behavior coverage.

### Change

Add a resolver owned by `map-entries.ps1` that:

1. Splits a dotted entry key into segments.
2. Walks dictionaries directly, including a `list` child where applicable.
3. Resolves an included map only when an unresolved segment requires it.
4. Expands `entry.all` through the existing `Get-BuildAllChildren`.
5. Falls back to the current enumerating path for legacy or ambiguous forms
   until compatibility tests demonstrate that no fallback is needed.

Update `Get-MapEntries`, `Get-MapEntry`, and `Get-EntryDynamicParam` to use
the direct resolver for explicit keys. Keep `Get-MapEntryList` for help and
completion, which genuinely require enumeration.

### What stays

The following behavior must remain identical:

- dotted entry names and nested `list` containers;
- `qbuild entry.all`;
- include prefixes and include precedence;
- missing-entry errors;
- object maps passed through `-map`;
- map and entry `_settings` resolution.

### Tests and measurements

Add tests in `test/configmap.tests.ps1` for direct lookup of:

- a top-level entry;
- nested entries;
- entries exposed by prefixed and unprefixed includes;
- `.all`;
- nonexistent keys.

Benchmark 100, 1,000, and 5,000 entries at depths 1, 3, and 6. The
acceptance target is warm p95 under 5 ms for a direct lookup in a 1,000-entry
map.

## 2. Build completion candidates in one traversal

### Why it matters

`Get-EntryCompletion` in `src/functions/completion.ps1` builds both flattened
and hierarchical lists, concatenates their keys, then calls
`Sort-Object -Unique`. This traverses the map twice and allocates two complete
ordered dictionaries for every completion request.

### Change

Introduce one completion traversal that adds each supported key form to an
ordered set:

- the hierarchical key;
- the flattened alias, where that form is supported;
- generated `.all` entries.

Use a `HashSet[string]` only for duplicate detection and retain the existing
traversal order for returned completions. Apply `wordToComplete` while walking
when doing so cannot hide a possible child match.

Remove the second `Get-CompletionList` call and the global
`Sort-Object -Unique` call after tests prove the completion order remains
compatible.

### What stays

Completion must still return all currently supported hierarchical and flattened
forms, generated `.all` entries, and the special `!init` and `!settings`
values provided by `Invoke-QBuild`.

### Tests and measurements

Extend `test/qbuild.tests.ps1` with fixtures containing duplicate flattened and
hierarchical keys. Assert both completion contents and order.

Measure empty-prefix, matching-prefix, and no-match completion for the same
map-size/depth matrix. The initial target is warm p95 under 25 ms for a
1,000-entry map.

## 3. Cache included maps within an operation

### Why it matters

`Merge-IncludeDirectives` in `src/functions/completion.ps1` dot-sources each
included `.build.map.ps1` and calls `Add-BaseDir` whenever the tree is walked.
The current completion path can therefore load the same included map twice in
one request. The settings walker has a separate per-call include cache in
`src/functions/settings.ps1`, so include loading is not consistently shared.

### Change

Pass a map-operation context through resolution and enumeration. It should
contain:

- included maps keyed by canonical map-file path;
- a loading set for circular-include protection;
- optional flattened and hierarchical indexes generated during the operation.

Reuse an included map from this context after it has been loaded and processed
with `Add-BaseDir`. Do not introduce a cross-command cache in this change:
map files are executable PowerShell and may intentionally be dynamic.

After operation-scoped caching is proven correct, consider a persistent cache
only with explicit freshness checks using canonical path and file metadata
(`LastWriteTimeUtc` and length).

### What stays

Includes remain executable map files; include failures keep their current
warning behavior; and map changes must be visible on the next command.

### Tests and measurements

Add a test seam around included-map loading. Assert that:

- repeated references to one include load it once per operation;
- circular includes terminate;
- separate command invocations reload the include;
- prefixed and unprefixed includes retain their existing keys.

Benchmark one, ten, and fifty includes, including nested includes. Report
latency and included-map load count.

## 4. Avoid duplicate root-map imports per command

### Why it matters

`Invoke-QBuild` in `src/functions/qbuild.ps1` imports a map in `dynamicparam`
and imports it again in `process`. `Invoke-QConf` has the same broad pattern.
For parameterized commands, this repeats file discovery, dot-sourcing, and
base-directory processing before any entry script has run.

### Change

Use the map-operation context to reuse the root map from dynamic parameter
discovery in processing when both phases target the same resolved path and
freshness token. If that lifecycle cannot be safely shared by PowerShell
parameter binding, retain the current behavior rather than caching a dynamic
map incorrectly.

### What stays

Map-file dot-sources remain visible in the invoking scope, and dynamic maps
must not have stale parameters or stale command bodies.

### Tests and measurements

Use a controlled map fixture that increments a test-visible import counter.
Verify parameterized `qbuild` and `qconf` commands run correctly and record
whether the root map is imported once or twice. Measure cold-process and
warm-session invocation separately.

## 5. Reuse static scriptblock parameter metadata

### Why it matters

`Get-ScriptArgs` in `src/functions/completion.ps1` walks a scriptblock AST and
constructs runtime-defined parameters. `Invoke-EntryCommand` in
`src/functions/invoke-entry.ps1` calls it again only to determine which bound
parameters should be forwarded.

### Change

Cache immutable parameter descriptors in the operation context: names, static
types, and static `ValidateSet` values. Rebuild a
`RuntimeDefinedParameterDictionary` when PowerShell requires one, but use the
cached parameter-name set in `Invoke-EntryCommand`.

Never cache the result of a `ValidateSet` reference that executes a scriptblock
beyond the current invocation.

### Tests and measurements

Preserve tests for typed parameters, switches, static `ValidateSet`, and
scriptblock-backed `ValidateSet`. Measure a parameterized no-op command with
zero, one, and multiple parameters.

## 6. Remove repeated plugin sorting

### Why it matters

`Invoke-ConfigMapPluginHooks` in `src/functions/plugins.ps1` sorts all plugins
on each hook invocation even though priorities normally change only when
plugins are registered.

### Change

Maintain a priority-ordered plugin collection when plugins are added or
removed. Dispatch hooks in that collection's existing order.

### Tests and measurements

Add coverage for priority order and for a handled hook short-circuiting later
hooks. Benchmark dispatch with zero, one, and ten plugins.

## Benchmark harness and reporting

Add a focused performance script or opt-in Pester tag so normal unit-test runs
remain fast. It must:

1. import the module once for warm tests;
2. run an unmeasured warmup;
3. record at least 50 warm samples;
4. report median, p95, min, max, and allocated bytes;
5. run cold-process scenarios in separate `pwsh -NoProfile` processes;
6. validate command output and completion results as well as timing.

Use this helper shape:

```powershell
function Measure-MedianMilliseconds {
    param(
        [int]$Iterations = 50,
        [scriptblock]$Action
    )

    & $Action
    $samples = 1..$Iterations | ForEach-Object {
        (Measure-Command $Action).TotalMilliseconds
    } | Sort-Object

    [pscustomobject]@{
        MedianMs = $samples[[int]($samples.Count / 2)]
        P95Ms    = $samples[[int][math]::Floor($samples.Count * 0.95)]
        MinMs    = $samples[0]
        MaxMs    = $samples[-1]
    }
}
```

Record the baseline before each implementation step and compare like-for-like
fixtures. Do not claim an improvement unless output behavior, ordering, and
error behavior are equivalent to the pre-change baseline.
