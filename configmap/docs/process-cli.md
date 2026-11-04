# Standalone qrun and qconf (deprecated)

`qrun` and `qconf` are the standalone CLIs behind the `steps` and `options` process types. They still work but print a deprecation warning. Use `qbuild` with `_settings.process` instead:

```powershell
@{
    bootstrap = @{ _settings = @{ process = 'steps' };   ... }   # was: qrun
    storage   = @{ _settings = @{ process = 'options' }; ... }   # was: qconf
}
```

The legacy map values `process = 'qrun'` and `process = 'qconf'` are still accepted and mean `steps` and `options`.

| Old | New |
|-----|-----|
| `qrun bootstrap` | `qbuild bootstrap` |
| `qrun bootstrap -Check` | `qbuild bootstrap -Check` |
| `qconf get -entry storage` | `qbuild storage` |
| `qconf set -entry storage -value prod` | `qbuild storage -value prod` |

## Steps options

```powershell
qbuild bootstrap            # run pending steps
qbuild bootstrap -Force     # rerun every step
qbuild bootstrap -Check     # run each step's `check` and sync the cached state; never runs `exec`
qbuild bootstrap -Reset     # forget the cached state
qbuild bootstrap.prepare    # run one step
```

```powershell
bootstrap = [ordered]@{
    _settings = @{ process = 'steps'; forceCheck = $true }   # check before every run
    prepare   = @{ exec = { ./prepare.ps1 }; check = { Test-Path prepared.txt } }
}
```

With `forceCheck`, each step's `check` runs right before that step, so it sees the effects of earlier steps; a process-level `check` still runs once up front.

`check` is a handler only in a steps context (on a steps process entry, or next to a scriptblock `exec`). Elsewhere it is an ordinary entry name, so `qbuild check` can run a `check = { ... }` entry.
