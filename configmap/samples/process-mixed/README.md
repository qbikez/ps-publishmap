# Mixed process sample

One `.build.map.ps1` that combines every process type: plain `exec` commands, `steps` processes and `options` entries (hand-written and templated).

```powershell
Import-Module ../../configmap.psm1 -Force
Set-Location $PSScriptRoot

qbuild list                     # commands, steps status and options in one listing

# exec
qbuild build -Configuration Release

# steps
qbuild bootstrap                # prepare -> restore -> verify, with persisted state
qbuild bootstrap.restore -Follow
qbuild short-lived-token        # forceCheck: reissues the token once its check fails
qbuild !state clean bootstrap

# options
qbuild storage set prod         # hand-written get/set
qbuild endpoint -value prod     # appsettings template
qbuild api -value prod          # dotenv template
qbuild secrets -value local     # user-secrets template (needs the .NET SDK)
qbuild env set dev -tenant abc  # extra parameters are passed to the entry
```

`endpoint_override` shows a custom `set` that wraps the template through `$_context.base.set`.
