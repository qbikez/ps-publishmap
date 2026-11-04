# Hierarchical build map sample

Nested hashtables group commands; dot notation addresses them. Groups and flat entries can be mixed in one map.

```powershell
Import-Module ../../configmap.psm1 -Force
Set-Location $PSScriptRoot

qbuild list                                       # all commands, grouped
qbuild frontend.build -Environment production
qbuild backend.test -Coverage
qbuild docker.up -Detached -Profile production
qbuild deploy.production -Tag v1.2.3 -Force

qbuild frontend.<TAB>                             # build, test, dev, lint
qbuild frontend.build -Environment <TAB>          # development, production
```

Groups: `frontend`, `backend`, `database`, `docker`, `deploy`, `utils`.
