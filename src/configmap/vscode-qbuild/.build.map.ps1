#requires -version 7.0

@{
    "install" = @{
        description = "Package the extension and install it into the local VS Code instance"
        exec        = {
            param(
                [ValidateSet('code-insiders', 'code')]
                [string]$Editor
            )

            npm run package
            if ($LASTEXITCODE -ne 0) {
                throw "Extension packaging failed."
            }

            $vsix = Get-ChildItem -File -Path '.publish' -Filter '*.vsix' |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if (-not $vsix) {
                throw "No VSIX was produced."
            }

            if (-not $Editor) {
                $Editor = @('code-insiders', 'code') |
                    Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } |
                    Select-Object -First 1
            }
            if (-not $Editor -or -not (Get-Command $Editor -ErrorAction SilentlyContinue)) {
                throw "VS Code CLI '$Editor' was not found. Install the 'code' or 'code-insiders' command from the Command Palette."
            }

            & $Editor --install-extension $vsix.FullName --force
            if ($LASTEXITCODE -ne 0) {
                throw "Installing $($vsix.Name) with $Editor failed."
            }

            Write-Host "Installed $($vsix.Name) with $Editor. Reload the editor to use it." -ForegroundColor Green
        }
    }

    "release" = @{
        description = "Bump the extension version, package the VSIX, and publish a GitHub release"
        exec        = {
            param(
                [ValidateSet('patch', 'minor', 'major', 'current')]
                [string]$Part = 'patch',
                [string]$Notes
            )

            $releaseArgs = @('scripts/release.js', $Part)
            if ($Notes) {
                $releaseArgs += @('--notes', $Notes)
            }

            node @releaseArgs
            if ($LASTEXITCODE -ne 0) {
                throw "Release failed."
            }
        }
    }
}
