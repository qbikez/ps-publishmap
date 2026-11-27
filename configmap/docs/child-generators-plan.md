# Plan: generic child-entry generators

Status: initial draft, not yet grilled.

## Goal

One mechanism for an entry to generate its child entries, regardless of the entry's process.
dotenv `keys = 'auto'` becomes one implementation of it, with today's behavior unchanged.

## Current state

Three unrelated mechanisms generate children today:

| Mechanism | Where | Strengths | Gaps |
|---|---|---|---|
| `list` key | any entry (`functions/completion.ps1:55`, `functions/map-entries.ps1:74`) | full entries; hashtable or lazy scriptblock | scriptblock gets no arguments (`Invoke-Command`), so state must be captured with `GetNewClosure()` (`samples/install`); replaces the entry's own keys instead of merging |
| Process `-GetEntries` | `Register-ConfigMapProcess` (`functions/custom-process.ps1:135`), used by `pkg` | on demand; gets a `$Context`; resolved by `Resolve-ConfigMapProcessGeneratedEntry` | returns name -> description only, not entries; per process, not per entry or template; build-only |
| dotenv `keys` | load hook in `handlers/qconf/qconf.ps1:653` -> `Expand-DotEnvKeyEntries` | real entries with get/set, `exclude`, explicit children win, delegate to the parent's get/set | eager on every map load; hard-coded to one template type; parent link kept in `_internal.parent` |

## Proposed design

### 1. Generator contract

An entry-level `children` command:

```powershell
children = {
    param($_context)
    # $_context.self = the entry; $_context.base.children = the default generator, if any
    [ordered]@{ API_URL = @{ description = '...'; get = {...}; set = {...} } }
}
```

- Returns an ordered name -> entry dictionary of full entries.
- Pure: reads files, writes nothing, never touches the map.
- `children` joins the reserved keys in both languages (`functions/languages.ps1`, `handlers/qconf/qconf.ps1:5`).

### 2. Defaults by `_template` type

- Add a `children` slot next to `get` / `set` / `sensitive` in `handlers/qconf/entry-types.map.ps1`.
- `Add-ConfigEntryTypeCommands` fills it in when the map omits it, and stores the default on `_internal.base.children`, the same way get/set work.
- An author-supplied `children` wins and can wrap `$_context.base.children` (filter, rename, add).

### 3. Merging

- Final children = generated children + explicit child keys of the entry. Explicit wins on a name clash.
- A generated child never replaces a reserved key.
- `exclude` stays a dotenv template option (implemented inside its generator), not a generic feature. *(Open question 2.)*

### 4. Parent link

- When the runtime invokes a generated child (`Invoke-EntryCommand`), it sets `$_context.parent` to the generating entry.
- dotenv children use `$_context.parent` instead of `_internal.parent` / `parentName`.

### 5. One resolver

A single function, e.g. `Get-EntryChildren -Entry -OperationContext`, that:

1. calls `children` (lazily, cached per operation context),
2. merges with explicit keys,
3. attaches `_baseDir` and the parent link to each generated child.

Every consumer calls it: completion (`Get-CompletionList`), lookup (`Get-MapEntries`, `Find-MapEntry` enumeration fallback), `list` / `help`, settings inheritance (`Get-ConfigMapSettingsForPath`), and the discovery cache.

### 6. Timing and cache

- Generators run lazily, on lookup / completion / list, not at map load.
- A generator reports its input files (dotenv: the keys file, e.g. `.env.example`). The resolver adds them to the discovery cache dependencies, so editing `.env.example` invalidates cached completion. This likely fixes a current staleness bug (unverified; add a test first).

## Phases

Each phase lands green with tests written first (see AGENTS.md).

1. **Resolver + `children` key.** Add the `children` contract, the merge rules and `Get-EntryChildren`. Wire completion and lookup. Tests: a hand-written `children` scriptblock on an `exec` entry and on an `options` entry; explicit child wins; `$_context.self` is set.
2. **Template default + override.** Add the `children` slot to the type table, the fill-in and `$_context.base.children`. Tests: an override wraps the base and filters a key.
3. **Move dotenv onto it.** Implement `dotenv.children` from `Resolve-DotEnvKeysFile` / `Read-DotEnvKeyInfo` / `New-DotEnvKeyEntry`; drop the `dotenv-entries` load hook for keys (the lazy `options` closure may stay or move separately). The existing per-key tests in `test/qconf-types.tests.ps1` must pass unchanged. Switch the parent link to `$_context.parent`.
4. **Cache dependencies.** The generator reports its input files; add a regression test for editing `.env.example`.
5. **Fold in `list` and `-GetEntries`** *(optional, later)*. A `list` scriptblock gets `$_context`; `-GetEntries` results become generated children whose `exec` calls the process. Keep both public contracts working.
6. **Docs.** README (map keys, `_template`), `samples/dotenv`, `skills/qbuild-templates`.

## Backwards compatibility

- `keys`, `exclude`, explicit-child-wins and per-key delegation to the parent's get/set keep their current behavior.
- `list` keeps replacing the entry's own keys unless open question 3 decides otherwise.
- `-GetEntries` handlers keep their signature.
- Perf: lazy generation should help large maps; check with `test/perf/Compare-Perf.ps1 -Base master` (`workspace-M`, `samples`).

## Open questions

1. Name of the key: `children`, `entries`, or reuse `list` as a scriptblock that takes `$_context`?
2. Should `exclude` be generic (applied by the resolver to any generator)?
3. Should `list` move to merge semantics, or stay "replace" for compatibility?
4. Should process handlers get a `children` default too (a `Register-ConfigMapProcess -Children` that supersedes `-GetEntries`)?
5. Cache granularity: is caching generated names in the discovery cache enough, or should generated entry metadata (descriptions, params) be cached too?
6. Nested generation: can a generated child have its own `children`?
