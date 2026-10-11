# qconf-as-process — behavioral tests

Companion to [`qconf-as-process.md`](./qconf-as-process.md).
Format: **command → expected result**.

Assumes a file-backed map like:

```powershell
# .build.map.ps1
build = { "built" | Set-Content build.txt }
storage = @{
  process = 'qconf'
  options = @{ local = 'L'; prod = 'P' }   # or scriptblock returning that
  get = { … return current … }
  set = { param($ctx,$key,$value) … write marker … }
}
```

## Coexistence with qbuild

| Command | Expected |
|---------|----------|
| `qbuild -map f build` | Runs built-in entry; `build.txt` written. Conf entry untouched. |
| `qbuild -map f storage` | Delegates to qconf (get); does **not** look for `exec`. |

## Get (default run)

| Command | Expected |
|---------|----------|
| `qbuild -map f storage` | Exit 0; get runs; pipeline/host shows current Active/Value (or test marker from get). |
| `qbuild -map f missing` | Throws / non-zero: entry not found. |
| `qconf -map f storage` | Same get behavior as via qbuild (standalone parity). |

## Set (opaque `-value` = option key)

| Command | Expected |
|---------|----------|
| `qbuild -map f storage -value local` | Exit 0; set runs with key `local`; option payload applied (marker / file reflects `L`). |
| `qbuild -map f storage -value prod` | Set applies `prod` payload. |
| `qbuild -map f storage -value nope` | Throws / error: unknown option key. |
| `qbuild -map f storage` *(after set local)* | Get reports Active=`local` (or equivalent). |

## List integration

| Command | Expected |
|---------|----------|
| `qbuild -map f list` | Output includes `storage` row; shows status/summary (Active and/or options), not a qrun step tree. |
| `qconf -map f list storage` | Same single-entry summary as the list row (Active, Value/Options). |
| `qbuild -map f list` *(after `storage -value prod`)* | Storage row reflects Active=`prod`. |

## Discovery / opaque params

| Command | Expected |
|---------|----------|
| `qconf -map f !complete -params -entry storage` | Stdout includes `value` (one name per line); exit 0. |
| `qbuild -map f storage -value <Tab>` *(or dynparam bind)* | `-value` is accepted (discovered); completes or binds option keys via qconf. |
| `qconf -map f !complete -word sto` | Stdout includes `storage`; exit 0. |

## Errors / boundaries

| Command | Expected |
|---------|----------|
| Entry with get/set but **no** `process=qconf` | `qbuild` treats as normal build entry → fail (no `exec`), not silent qconf. |
| `qbuild -map f storage -Follow` | Unknown/opaque param not in `!complete` → bind error (or ignored only if remaining-args; prefer error). |
| In-memory `-map $hashtable` via qbuild for conf process | Fail clearly: path-only handoff required (or test only uses files). |

## Standalone qconf regression (not via qbuild)

| Command | Expected |
|---------|----------|
| `qconf -map f -command get -entry storage` | Still works (legacy), same get result. |
| `qconf -map f -command set -entry storage -value local` | Still works (legacy set). |
| `qconf -entry !init` *(no map)* | Creates `.configuration.map.ps1`. |

## Smoke (sample)

| Command | Expected |
|---------|----------|
| Copy hybrid sample → `qbuild clean` / `qbuild build` | Build entries work. |
| `qbuild storage` / `qbuild storage -value local` | Conf process works against sample options. |
| `qbuild list` | Both build commands and conf process row appear. |

## Minimal first slice

Enough to drive the qconf reshape:

1. `qbuild build` → build marker
2. `qbuild storage` → get succeeds
3. `qbuild storage -value local` → set marker / Active=local
4. `qbuild storage` again → Active=local
5. `qbuild list` → contains `storage` + active/options signal
6. `qconf !complete -params -entry storage` → contains `value`
