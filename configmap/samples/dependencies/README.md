# Task dependencies sample

An entry lists the entries to run before it in `_dependsOn`, by path from the map root, or as a sibling in its own group with `./name` (`./lint` on `api.build` is `api.lint`; `.
ame` works too). `..` is not supported; use the full path from the root. qbuild runs them depth-first, each at most once per call, then runs the entry.

```powershell
Import-Module ../../configmap.psm1 -Force
Set-Location $PSScriptRoot

qbuild pack            # lint, restore, build, test, api.lint, api.build, then pack
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
-> api.lint (dependency of api.build)
linting api
-> api.build (dependency of pack)
building api
packing
```

A dependency that throws or exits non-zero stops the run before the entry. A cycle or an unknown entry name fails before anything runs.
