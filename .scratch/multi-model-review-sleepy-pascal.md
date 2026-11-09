# Multi-model review: `claude/sleepy-pascal-d09mzn`

- **Date:** 2026-11-05
- **Scope:** `git diff master...HEAD` (ignore untracked `.scratch/` and `configmap/samples/write/`)
- **Reviewers:** `grok-4.7-xhigh`, `composer-2.5-fast`
- **Parent synthesis:** Composer (Cursor agent)

## Intent

This branch adds qbuild task dependencies: `_dependsOn` lists entries to run before an entry (run-once per identity of path+args, depth-first, cycles detected, `-NoDeps` skip). It renames the old discovery-cache file-list key from `_dependsOn` to `_cacheDependsOn`, with a one-shot warning when `_dependsOn` looks like a file path. Also includes case-insensitive entry tab completion, dotenv exclude hiding from parent value, docs, sample, and substantial Pester coverage.

## Verdict

Core ledger/`-NoDeps` design looks solid and well tested; do not treat run-once as reliable for `group.all` or case-mismatched entry/arg names.

---

## Act on

| Finding | Who | Why |
|---|---|---|
| **`group.all` re-runs children that already ran as deps** — `.all` uses `Invoke-EntryWrapper`, which ignores the ledger; Concurrently can start a sibling twice | grok | Breaks the documented run-once contract for a common shape |
| **Run identity is case-sensitive; map/completion are not** — `qbuild test,Build` can run `build` twice; arg name case similarly splits identities | grok | Silent double-run under normal PS usage |
| **Cycle stack is by entry `Key`, not identity** — `build` depending on `build -Configuration Release` throws `build -> build` | both (composer stronger) | Blocks a plausible two-pass same-entry dep; message also hides args |

### Details

#### `group.all` re-runs children that already ran as a dependency (warning — grok)

**Location:** `Get-ConfigMapDependencySource` (`configmap/functions/dependencies.ps1`), `Invoke-ConfigMapExecProcess` (`configmap/handlers/exec/exec.ps1`)

`api.all` collects `_dependsOn` from the group and from each child, then runs those dependencies through `Invoke-QBuild`. The `.all` handler then invokes every child with `Invoke-EntryWrapper`, which never reads `RanAsDependency` or `Completed`.

If `api.test` depends on `api.build`, `qbuild api.all` runs `api.build` once as a dependency and again as a member. The same thing happens for `ship` depending on `api.all`. With `Concurrently`, the second run is a parallel child, so a server or publish step can start twice. The new tests only cover children that depend on an outside task (`restore` / `gen`), not on a sibling.

**Suggestion:** When executing a target, skip it when its identity is already in the ledger, or do not pre-run a dependency that this `.all` expansion will invoke itself.

#### Run identity is case-sensitive; entry lookup is not (warning — grok)

**Location:** `ConvertTo-ConfigMapRunIdentity` (`configmap/functions/dependencies.ps1`), request identity in `configmap/host/qbuild.ps1`

`HashSet[string]` uses ordinal comparison. The requested identity is the raw `-entry` string plus bound parameter names as declared. Map lookup uses PowerShell `-eq` / `-ne`, which ignore case, and this branch’s completion is ordinal-ignore-case.

`qbuild test,Build` with `test` depending on `'build'` runs `build` as a dependency (identity `build`), then runs `Build` again because `RanAsDependency` does not contain `Build`. The same split happens for argument names: `args = @{ configuration = 'Release' }` does not match a parameter declared as `$Configuration`.

**Suggestion:** Normalize the entry key to the map’s key, and argument names to the declared parameter names, before building the identity.

#### Cycle detection keyed by entry path, not run identity (warning — both)

**Location:** `Add-ConfigMapDependencyPlanItem` / `Resolve-ConfigMapDependencyPlan` (`configmap/functions/dependencies.ps1`)

Planning seeds the cycle stack with the requested `EntryKey` before walking `_dependsOn`. Any dependency whose resolved `Key` equals that entry is treated as a cycle, even when `Identity` differs (different `args`).

Repro: `_dependsOn = @(@{ entry = 'build'; args = @{ Configuration = 'Release' } })` on `build` throws `Dependency cycle: build -> build`.

**Suggestion:** Seed the stack empty, or push `ref.Identity` (or only push while recursing and compare identity for same-key/different-args chains). Document if same-key multi-arg deps are intentionally forbidden.

---

## Consider

| Finding | Who | Why |
|---|---|---|
| **Windows `..\` / `.\` handling** — only `../` rejected; `.\` not sibling-normalized | both | Real on this repo’s primary OS; easy fix |
| **Legacy warning false positives** — `./name` + file on disk, or file-like task names; missing files may not warn | both | Migration UX noise / misses |
| **`$LASTEXITCODE` after dep invoke** — Concurrently probe / steps “Succeeded” then fail on leftover exit code | grok | Can false-fail or skip work on retry |
| **Identity string encoding** — `;` / `,` in values can collide | grok | Unlikely in practice; cheap to harden |
| **`-NoDeps` does not override `RanAsDependency` skip** | composer | Only if you want “force this body again” semantics |

### Details

#### `../` and `./` only accept forward slashes (warning — both)

**Location:** `ConvertTo-ConfigMapDependencyRef` (`configmap/functions/dependencies.ps1`)

`../` is rejected only when the string starts with `../`. `.\lint` is not rewritten to a sibling, and `..\build` is not rejected. Both are looked up as entry names, fail, and also trip the legacy file warning because of the backslash. `./../build` starts with `./`, so it bypasses the `../` check. Test coverage is only `'../build'`.

**Suggestion:** Normalize separators before the prefix checks, and reject any `..` segment.

#### Legacy `_dependsOn` file warning misfires (warning — both)

**Location:** `Write-ConfigMapLegacyDependsOnWarning` (`configmap/functions/discovery-cache.ps1`)

An item warns when it contains a separator other than a leading `./`, or when `Test-Path -PathType Leaf` is true.

Effects:

- A real task named `build` warns whenever a file named `build` exists in the map directory. `./lint` is documented as a sibling task, but it is still tested as a file path.
- A file list entry with no slash and no file yet (`helpers.ps1` not generated, or not next to the map) does not warn, and it is no longer recorded in the cache. Discovery will not rebuild when that file appears.
- Task names that look like files (e.g. `helpers.ps1`) get a migration warning during cache discovery; the same string still fails at run time as “not found” with a `_cacheDependsOn` hint.

**Suggestion:** Do not treat “exists on disk” as sufficient for `./name`. Warn on a file-like token (extension or separator) even when the file is absent; or warn only when the string is not a resolvable entry key.

#### Non-zero `$LASTEXITCODE` is not always the dependency’s own failure (warning — grok)

**Location:** `Invoke-ConfigMapDependencyPlan` (`configmap/functions/dependencies.ps1`); steps state in qrun handler

The plan sets `$global:LASTEXITCODE = 0`, then throws if it is non-zero after `Invoke-QBuild` returns. That catches a scriptblock that sets exit 1 (covered by tests). It also catches anything the handler left behind:

- For a `group.all` dependency with Concurrently enabled, `Test-ConcurrentlyAvailable` runs `npx` and, when the package is missing, can leave `$LASTEXITCODE` non-zero even when children succeed in-process.
- A `steps` dependency may mark the step `Succeeded`, then fail because `$LASTEXITCODE` is non-zero; the next run can skip the step and the dependency can pass without doing the work.

**Suggestion:** Snapshot `$LASTEXITCODE` only around the entry script, or have steps fail the step on a non-zero code before writing `Succeeded`. Ignore exit codes left by plugin probes that decline the hook.

#### Identity encoding collides (warning — grok)

**Location:** `ConvertTo-ConfigMapRunIdentity` (`configmap/functions/dependencies.ps1`)

The identity is `$Key|$name=$value` pairs joined with `;`, and arrays are joined with `,`, with no escaping. These are the same identity, so the second run is skipped:

- `@{ X = 'a;Y=b' }` and `@{ X = 'a'; Y = 'b' }`
- `@{ Files = @('a,b','c') }` and `@{ Files = @('a','b','c') }`

**Suggestion:** Encode length-prefixed or escaped values, or hash a structured payload instead of a delimited string.

#### `-NoDeps` does not force re-run after dep (warning — composer)

**Location:** `Invoke-QBuild` (`configmap/host/qbuild.ps1`)

`RanAsDependency` skip runs before the main handler and is not gated on `-NoDeps`. In `qbuild test, build`, `build` is skipped after it ran as a dep; `-NoDeps` on the invocation does not force a second run of the requested entry.

**Suggestion:** If `-NoDeps` should mean “run this entry body even if it already ran as a dependency”, skip the `RanAsDependency` check when `$NoDeps` is set (and document).

#### Breaking rename / unmigrated maps (warning — both)

Cache invalidation reads only `_cacheDependsOn`. Old root `_dependsOn` file lists no longer affect the discovery cache; users get warnings (when heuristics match) and broken task behavior until renamed. In-repo samples/docs are migrated; README documents the break.

**Suggestion:** Call out in release notes that stale completion can persist until cache rebuild/migration.

---

## Noted

- **`exec = @('a','b')` does not run those sub-entries’ `_dependsOn`** (grok nit) — Sub-entries run via `Invoke-EntryCommand`, not `Invoke-QBuild`. README already contrasts the two mechanisms; worth one sentence that a nested entry’s own `_dependsOn` is dropped.
- **Empty `_dependsOn = @()`** (composer nit) — Treated as having dependencies; Concurrently/tmux may add unnecessary `-NoDeps`. Harmless; could require non-empty collection.
- **Missing regression test: group-level `_dependsOn` only + Concurrently** (composer nit) — Children without their own `_dependsOn` correctly omit `-NoDeps` and rely on the parent plan; lock that shape with a test.
- **options `set`/`prod` vs `ProcessAction`/`ProcessValue` are different identities** (grok nit) — Both reach the handler, but a later request may not count as the dependency that already ran.
- **Cycle message omits arguments** (grok nit) — Debug-versus-Release edge can look like a plain self-loop.

---

## Dismissed / disagreement

- **`$PSBoundParameters.Remove('NoDeps')` leak into nested calls:** grok checked nested copies — array path copies bound parameters before remove; each `Invoke-QBuild` has its own dictionary. Not a bug.
- **Self-dep with different args “is always a real cycle”:** grok softened this; composer treats it as a product bug. Prefer treating intentional Debug→Release same-key deps as **act on** unless you explicitly forbid them in the contract.

---

## Per-model overall risk assessments

### grok-4.7-xhigh

The owner/finally ledger split and `-NoDeps` on tmux and concurrently children match the tests for a single target. The run-once guarantee fails for `group.all` (and a concurrently child) when a member is also someone’s dependency, and for entry or argument names that differ only by case. Exit-code failures can also fire when a handler probe leaves `$LASTEXITCODE` set, and a `steps` dependency can record success before that failure, so a retry skips the work. Do not treat the dependency contract as holding for `.all` or for case-insensitive invocation until those two are fixed.

### composer-2.5-fast

Core ledger sharing, run-once by `Identity`, depth-first planning, plugin `-NoDeps` / tmux in-process deps, and failure handling are coherent and well covered by Pester. The main correctness gaps are cycle detection keyed by entry path (blocking same-key deps with different args), incomplete parent-path rejection on Windows, and legacy/cache heuristics that can warn or confuse maps using file-like task names or `./` siblings that collide with files on disk. The `_dependsOn` → `_cacheDependsOn` rename is a deliberate breaking change; unmigrated maps can get stale discovery until migrated, with moderate operational risk rather than security risk.

---

## Agent IDs (for resume)

- grok: `e5801a3a-beec-4650-9ea3-c3e55930c013`
- composer: `1caac14a-603c-43dc-994f-dfd51dc498b5`
