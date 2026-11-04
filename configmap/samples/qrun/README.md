# Steps process sample

Durable multi-step processes: bootstrap a workspace, run a release that fails until approved, then clean up. Steps only create files under `./workspace`.

This sample uses the standalone `qrun` CLI with `.process.map.ps1`, which is deprecated. In a build map, the same entries run through `qbuild` with `_settings.process = 'steps'` (see `samples/process-mixed`).

```powershell
Import-Module ../../configmap.psm1 -Force
Set-Location $PSScriptRoot

qrun list
qrun bootstrap                          # runs all steps; a second run skips them
qrun bootstrap -Status
qrun bootstrap -Force                   # rerun everything
qrun bootstrap.restore -Follow          # one step and the ones after it
qrun bootstrap.write-config -Environment prod   # step parameters come from param()

qrun release                            # fails at the gate
Set-Content ./workspace/APPROVED ok
qrun release                            # resumes; finished steps are skipped

qrun !state show bootstrap
qrun !state clean
qrun clean                              # delete workspace/ and state
```

| Process | Steps |
|---------|-------|
| `bootstrap` | prepare, write-config, restore, compile, smoke-test, package |
| `release` | tag, notes, gate, publish |
| `clean` | remove workspace and state |
