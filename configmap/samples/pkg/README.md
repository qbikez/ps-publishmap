# Package-script qbuild sample

Entries with `_settings = @{ process = "npm" }` or `"bun"` proxy to `<tool> run <script>`
in the entry's directory. The script list comes from `package.json` and is read lazily
(on invoke, list and tab completion), never when the map loads.

```powershell
Import-Module ../../configmap.psm1 -Force
Set-Location $PSScriptRoot

qbuild list              # shows web and web-bun next to plain entries
qbuild web               # lists package.json scripts (same as `qbuild web list`)
qbuild web build         # npm run build
qbuild web greet -- Ada  # npm run greet -- Ada
qbuild web-bun build     # bun run build (requires bun)
qbuild web <tab>         # completes list, build, greet
```

npm only forwards arguments that follow `--`, so qbuild inserts it for you; bun gets the
trailing arguments as-is. An unknown script name throws and names the available ones.
