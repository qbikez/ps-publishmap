# Task dependencies sample

An entry lists the entries to run before it in `_dependsOn`, by path from the map root. qbuild runs them depth-first, each at most once per call, then runs the entry.

```powershell
Import-Module ../../configmap.psm1 -Force
Set-Location $PSScriptRoot

qbuild pack            # lint, restore, build, test, api.build, then pack
qbuild test            # restore, build, then test
qbuild test -NoDeps    # only test
```

`restore` is declared by `build`, `test` and `api.build`, but runs once:

```
> qbuild pack
-> lint (dependency of pack)
linting
-> restore (dependency of test)
restoring packages
-> build (dependency of test)
building
-> test (dependency of pack)
running tests
-> api.build (dependency of pack)
building api
packing
```

A dependency that throws or exits non-zero stops the run before the entry. A cycle or an unknown entry name fails before anything runs.
