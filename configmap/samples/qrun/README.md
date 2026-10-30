# qrun process sample

A self-contained demo of durable multi-step processes: bootstrap an app workspace, run a release checklist that fails until approved, then clean up.

No external tools required — steps only create files under `./workspace`.

## Setup

```powershell
Import-Module ..\..\configmap.psm1 -Force
cd samples\qrun
```

## Processes

| Process | What it does |
|---------|----------------|
| `bootstrap` | prepare → write-config → restore → compile → smoke-test → package |
| `release` | tag → notes → **gate** (fails until approved) → publish |
| `clean` | delete `workspace/` and `.configmap/` state |

## Quick tour

### 1. Full bootstrap

```powershell
qrun                 # same as: qrun !state
qrun list
qrun bootstrap
qrun bootstrap -Status
```

Re-run skips succeeded steps:

```powershell
qrun bootstrap          # all SKIP
qrun bootstrap -Force   # rerun everything
```

### 2. Single step / follow

Dot paths work like `qbuild`. Add `-Follow` to continue through later steps:

```powershell
qrun bootstrap -Reset
qrun bootstrap.prepare                 # only that step
qrun bootstrap.restore -Follow         # restore + later steps (priors must have succeeded)
qrun bootstrap.restore -Follow -Force  # same, but allow skipping incomplete prior steps
```

### 3. Step parameters

Parameters come from each step's `param()` block (same dynamic-param system as `qbuild`):

```powershell
qrun bootstrap -Reset
qrun bootstrap.write-config -Environment prod
qrun bootstrap.restore -Follow -Configuration Release
```

> Note: when running multiple steps, bound parameters are passed through to steps that declare them.

### 4. Failure + resume (`release`)

```powershell
qrun release
# → FAIL on gate (no workspace/APPROVED yet)

qrun release -Status

# Approve, then resume — tag/notes are skipped
Set-Content .\workspace\APPROVED 'ok'
qrun release
```

### 5. Inspect / clean state

```powershell
qrun !state              # show all process state
qrun !state show
qrun !state show bootstrap
qrun !state clean bootstrap
qrun !state clean        # wipe all process state for this map
```

Or remove workspace artifacts too:

```powershell
qrun clean
```

## Layout after a successful run

```
samples/qrun/
  .process.map.ps1
  workspace/
    config/appsettings.json
    src/packages.lock
    src/Program.ps1
    artifacts/Debug/...
    artifacts/contoso-Debug.zip
    VERSION / CHANGELOG.md / APPROVED / publish/   # after release
  .configmap/process/.../*.state.json              # durable step state
```
