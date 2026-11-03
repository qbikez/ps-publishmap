# Playwright qbuild sample

Shows `[ValidateSet('@key')]` driving tab completion from a command's output: the `test`
entry's `testNames` scriptblock runs `npx playwright test --list` and turns each listed test
into a completion value. The dummy tests use only `expect`, so no browsers need installing.

```powershell
Import-Module ../../configmap.psm1 -Force
Set-Location $PSScriptRoot
npm install

qbuild test                                # all 5 tests
qbuild test -testName <tab>                # math adds numbers, strings reverses text, ...
qbuild test -testName 'math adds numbers'  # runs 1 test
qbuild test -file <tab>                    # math.spec.js, strings.spec.js
qbuild test -file strings.spec.js          # runs 3 tests
qbuild test -testName nope                 # throws: value is not in the set
```

Limitations of the `@key` approach:

- The values are a `ValidateSet`, so anything outside the list (a partial name, a regex) is
  rejected rather than passed to `--grep`.
- `testNames` only runs when `-testName` itself is completed (each Tab press) and when a run
  passes `-testName` (to validate it). It is not cached, so each of those costs a
  `npx playwright test --list` (about a second); `qbuild test <tab>` and plain `qbuild test` do not.
- The entry must be a hashtable; a bare `test = { param(...) }` entry has no sibling key to
  resolve and silently gets no completion.
