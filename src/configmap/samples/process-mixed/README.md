# Mixed qbuild process sample

This `.build.map.ps1` mixes normal qbuild commands with an
`_settings.process=qrun` entry and an `_settings.process=qconf` entry.

```powershell
Import-Module ../../configmap.psm1 -Force
Set-Location $PSScriptRoot

qbuild list          # build commands, qrun status, and qconf summary
qbuild clean
qbuild build -Configuration Release
qbuild bootstrap     # runs prepare → restore → verify with persisted state
qbuild bootstrap.prepare
qbuild bootstrap.restore -Follow
qbuild storage get             # reads the active storage option
qbuild storage set prod        # activates the prod option
qbuild storage show            # same status formatting as the list row
qbuild endpoint                # reads appsettings.Development.json
qbuild endpoint -value prod    # writes Storage:BaseUrl for the prod preset
qbuild env set <tab>           # completes local, dev, prod
qbuild env set dev -tenant abc # option key + opaque -tenant
qbuild env get
qbuild !state
qbuild !state clean bootstrap
```

Entries without `_settings.process` use the default qbuild runner. Entries with
`_settings = @{ process = "qrun" }` are forwarded to the qrun step runner
(same map). The `storage`, `endpoint`, and `env` entries use `_settings = @{ process = "qconf" }`.
`endpoint` is an `appconfig` entry: it reads and writes `appsettings.Development.json`, and the option values are the setting keys.
`storage` and `env` supply their own get and set. qbuild forwards the process-owned `get`/`set` arguments and opaque parameters
(such as `-tenant`) without knowing qconf's semantics. The shorter
`qbuild storage` and `qbuild storage -value prod` forms remain supported.
