# step-check-switch

A `check` scriptblock of a `steps` entry that calls `qbuild <entry> -<switch>`.
The switch must reach the called entry: `chk -porcelain` returns an object, so the
step is `OK`. If the switch is dropped, `chk` prints `human mode`, returns `$null`
and the step is reported `MISSING`.

```powershell
cd samples/step-check-switch
qbuild p.s -check
```
