# Tmux dispatch sample

With `_settings.TmuxAutoWindow`, running `qbuild` inside tmux sends each entry to a window named after the entry path, creating it if needed. Outside tmux, entries run in the current shell.

```powershell
Import-Module ../../configmap.psm1 -Force
Set-Location $PSScriptRoot
tmux new-session -s dev

qbuild build.ui                          # runs in window "build.ui"
qbuild build.api -Configuration Release  # arguments are forwarded
qbuild build.all                         # one window per child
qbuild test.unit -- --filter MyTest      # passthrough args after -- too
```

Running an entry from its own window runs it there, without re-dispatching. `help`, `list` and `!init` always run locally, and so do in-memory maps.

Outside tmux, `build.all` runs the children in parallel through `npx concurrently` when `_settings.Concurrently` is on.

Turn dispatch off with `$env:QCONF_TmuxAutoWindow = '0'`.
