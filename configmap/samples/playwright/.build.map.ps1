#requires -version 7.0

# Playwright test runner with tab completion of test names and spec files.
# Try:
#   qbuild test                              # runs every test
#   qbuild test -testName <tab>              # completes names from `npx playwright test --list`
#   qbuild test -testName 'math adds numbers'
#   qbuild test -file <tab>                  # completes spec files
#   qbuild test -file strings.spec.js
#   qbuild test -testName nope               # rejected: not in the set

[ordered]@{
    test = [ordered]@{
        description = "Run Playwright tests, optionally filtered by test name or spec file"

        # Each line of `--list` looks like `  math.spec.js:4:5 › math › adds numbers`.
        # The ' › '-separated title path is joined with spaces because that is the string
        # Playwright's --grep matches against.
        testNames   = {
            Push-Location $PSScriptRoot
            try {
                npx playwright test --list 2>$null |
                    ForEach-Object {
                        if ($_ -match '^\s+\S+:\d+:\d+ › (.+)$') { $Matches[1] -replace ' › ', ' ' }
                    }
            }
            finally {
                Pop-Location
            }
        }

        specFiles   = {
            Get-ChildItem -Path (Join-Path $PSScriptRoot 'tests') -Filter '*.spec.js' |
                ForEach-Object Name
        }

        exec        = {
            param(
                [ValidateSet('@testNames')][string]$testName,
                [ValidateSet('@specFiles')][string]$file
            )

            $playwrightArgs = @('playwright', 'test')
            if ($file) { $playwrightArgs += "tests/$file" }
            if ($testName) { $playwrightArgs += @('--grep', [regex]::Escape($testName)) }

            npx @playwrightArgs
        }
    }
}
