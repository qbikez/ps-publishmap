#requires -version 7.0

# Package-script proxy: entries with _settings.process = 'npm' | 'bun' run package.json scripts.
# Try:
#   qbuild list
#   qbuild web               # lists package.json scripts
#   qbuild web build
#   qbuild web greet -- Ada  # arguments after the script name are forwarded
#   qbuild web <tab>         # completes script names
#   qbuild clean

[ordered]@{
    "clean"   = {
        Write-Host "plain exec entry next to the package-script entries" -ForegroundColor Gray
    }

    "web"     = [ordered]@{
        _settings   = @{ process = "npm" }
        description = "Frontend scripts from package.json (npm)"
    }

    "web-bun" = [ordered]@{
        _settings   = @{ process = "bun" }
        description = "Same package.json scripts, run with bun"
    }
}
