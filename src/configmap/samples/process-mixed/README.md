# Mixed qbuild + qrun process sample

This `.build.map.ps1` mixes normal qbuild commands with an
`_settings.process=qrun` entry.

```powershell
Import-Module ../../configmap.psm1 -Force
Set-Location $PSScriptRoot

qbuild list          # flat lines for clean/build; status tree for bootstrap
qbuild clean
qbuild build -Configuration Release
qbuild bootstrap     # runs prepare → restore → verify with persisted state
qbuild bootstrap.prepare
qbuild bootstrap.restore -Follow
qbuild !state
qbuild !state clean bootstrap
```

Entries without `_settings.process` use the default qbuild runner. Entries with
`_settings = @{ process = "qrun" }` are forwarded to the qrun step runner
(same map).
