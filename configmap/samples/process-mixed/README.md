# Mixed qbuild process sample

This `.build.map.ps1` mixes normal qbuild commands with `steps` process
entries, hand-written `options` entries, and appconfig / dotenv / user-secrets `_template` entries.

```powershell
Import-Module ../../configmap.psm1 -Force
Set-Location $PSScriptRoot

qbuild list          # build commands, steps status, and options summary
qbuild clean
qbuild build -Configuration Release
qbuild bootstrap     # runs prepare → restore → verify with persisted state
qbuild bootstrap.prepare
qbuild bootstrap.restore -Follow
qbuild short-lived-token       # _settings.forceCheck: issues workspace/token.txt
qbuild short-lived-token       # within 5s: check passes → SKIP
Start-Sleep 6
qbuild short-lived-token       # token expired: check fails → issues a new one
qbuild storage get             # reads the active storage option
qbuild storage set prod        # activates the prod option
qbuild storage show            # same status formatting as the list row
qbuild endpoint                # reads appsettings.Development.json
qbuild endpoint -value prod    # writes Storage:BaseUrl for the prod preset
qbuild api                     # reads .env via the dotenv template
qbuild api -value prod         # writes API_URL / API_KEY for the prod preset
qbuild secrets -value local    # writes Api:Key with dotnet user-secrets (needs the .NET SDK)
qbuild secrets                 # reads the secret; qbuild list shows <not read> instead
qbuild env set <tab>           # completes local, dev, prod
qbuild env set dev -tenant abc # option key + opaque -tenant
qbuild env get
qbuild !state
qbuild !state clean bootstrap
```

Entries without `_settings.process` use the default `exec` runner. Entries with
`_settings = @{ process = "steps" }` use the step runner (same map; standalone `qrun` is deprecated).
The `storage`, `endpoint`, `api`, `secrets`, and `env` entries use `_settings = @{ process = "options" }`
(standalone `qconf` is deprecated). Legacy process names `qrun` / `qconf` still normalize to these types.
`endpoint` uses `_template = "appsettings:appsettings.Development.json"` (or the long `_template = @{ type = "appconfig"; file = "..." }` form) so options fills in get/set; option values are the setting keys.
`endpoint_override` keeps the same template but overrides `set`, calling the inherited implementation via `& $_context.base.set ...` before extra work.
`api` uses `_template = "dotenv:.env"` (or `_template = @{ type = "dotenv"; file = "..." }`) the same way for `.env` files.
`secrets` uses `_template = "user-secrets:App.csproj"` (or `_template = @{ type = "user-secrets"; csproj = "App.csproj" }`) for the project's .NET user secrets. Its `shared` option copies another secret from the same project, and `set` fails if that secret is missing.
`storage` and `env` supply their own get and set. qbuild forwards the process-owned `get`/`set` arguments and opaque parameters
(such as `-tenant`) without knowing options semantics. The shorter
`qbuild storage` and `qbuild storage -value prod` forms remain supported.
