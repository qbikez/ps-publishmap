BeforeAll {
    $script:installScript = Join-Path $PSScriptRoot 'install.ps1'
    . $script:installScript

    $script:originalEditor = $env:QBUILD_EDITOR
    $script:originalVersion = $env:QBUILD_MAP_TOOLS_VERSION
    $env:QBUILD_EDITOR = $null
    $env:QBUILD_MAP_TOOLS_VERSION = $null
}

AfterAll {
    $env:QBUILD_EDITOR = $script:originalEditor
    $env:QBUILD_MAP_TOOLS_VERSION = $script:originalVersion

    @(
        'Get-QBuildMapToolsNextLink'
        'Select-QBuildMapToolsTag'
        'Select-QBuildMapToolsAsset'
        'Get-QBuildMapToolsEditorPath'
        'Resolve-QBuildMapToolsEditor'
        'Install-QBuildMapTools'
    ) | ForEach-Object {
        Remove-Item -LiteralPath "Function:\$_" -ErrorAction SilentlyContinue
    }
}

Describe 'qbuild Map Tools install script' {
    It 'installs only when the script is executed or piped to Invoke-Expression' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:installScript,
            [ref]$tokens,
            [ref]$errors
        )

        $errors | Should -BeNullOrEmpty
        $guard = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.IfStatementAst] -and
                $node.Clauses[0].Item1.Extent.Text -match 'InvocationName\s*-ne\s*''\.'''
            }, $true) | Select-Object -First 1

        $guard | Should -Not -BeNullOrEmpty
        $guard.Clauses[0].Item2.Extent.Text | Should -Match 'Install-QBuildMapTools'
    }

    It 'selects the highest qbuild Map Tools tag and ignores other refs' {
        $refs = @(
            [pscustomobject]@{ ref = 'refs/tags/v1.0.0' }
            [pscustomobject]@{ ref = 'refs/tags/qbuild-map-tools-v0.1.0' }
            [pscustomobject]@{ ref = 'refs/tags/qbuild-map-tools-v0.2.0' }
            [pscustomobject]@{ ref = 'refs/tags/qbuild-map-tools-v0.1.9' }
        )

        $selected = Select-QBuildMapToolsTag -Refs $refs

        $selected.Tag | Should -Be 'qbuild-map-tools-v0.2.0'
        $selected.Version | Should -Be ([version]'0.2.0')
    }

    It 'selects the requested version' {
        $refs = @(
            [pscustomobject]@{ ref = 'refs/tags/qbuild-map-tools-v0.1.0' }
            [pscustomobject]@{ ref = 'refs/tags/qbuild-map-tools-v0.1.1' }
        )

        $selected = Select-QBuildMapToolsTag -Refs $refs -Version '0.1.0'

        $selected.Tag | Should -Be 'qbuild-map-tools-v0.1.0'
    }

    It 'reports published versions when the requested version is missing' {
        $refs = @(
            [pscustomobject]@{ ref = 'refs/tags/qbuild-map-tools-v0.1.1' }
        )

        { Select-QBuildMapToolsTag -Refs $refs -Version '9.9.9' } |
            Should -Throw "*version '9.9.9' was not found*0.1.1*"
    }

    It 'rejects a version that is not major.minor.patch' {
        { Select-QBuildMapToolsTag -Refs @() -Version 'latest' } |
            Should -Throw "*major.minor.patch*"
    }

    It 'fails when no extension release exists' {
        { Select-QBuildMapToolsTag -Refs @([pscustomobject]@{ ref = 'refs/tags/v1.2.3' }) } |
            Should -Throw '*No qbuild Map Tools release was found*'
    }

    It 'reads the next GitHub page from a link header' {
        $link = '<https://api.github.com/repos/qbikez/ps-publishmap/git/matching-refs/tags/qbuild-map-tools-v?page=2>; rel="next", <https://api.github.com/repos/qbikez/ps-publishmap/git/matching-refs/tags/qbuild-map-tools-v?page=2>; rel="last"'

        Get-QBuildMapToolsNextLink -Link $link |
            Should -Be 'https://api.github.com/repos/qbikez/ps-publishmap/git/matching-refs/tags/qbuild-map-tools-v?page=2'
        Get-QBuildMapToolsNextLink -Link $null | Should -BeNullOrEmpty
    }

    It 'selects the VSIX asset from a GitHub release' {
        $release = [pscustomobject]@{
            tag_name = 'qbuild-map-tools-v0.1.1'
            assets   = @(
                [pscustomobject]@{ name = 'notes.txt'; browser_download_url = 'https://example.test/notes.txt' }
                [pscustomobject]@{
                    name                 = 'qbuild-map-tools-0.1.1.vsix'
                    browser_download_url = 'https://example.test/qbuild-map-tools-0.1.1.vsix'
                }
            )
        }

        $asset = Select-QBuildMapToolsAsset -Release $release

        $asset.Version | Should -Be ([version]'0.1.1')
        $asset.AssetName | Should -Be 'qbuild-map-tools-0.1.1.vsix'
        $asset.DownloadUrl | Should -Be 'https://example.test/qbuild-map-tools-0.1.1.vsix'
    }

    It 'fails when a release has no VSIX asset' {
        $release = [pscustomobject]@{
            tag_name = 'qbuild-map-tools-v0.1.1'
            assets   = @()
        }

        { Select-QBuildMapToolsAsset -Release $release } |
            Should -Throw '*does not include a VSIX*'
    }

    It 'returns editor install paths for VS Code, Cursor, and Insiders' {
        $paths = @(Get-QBuildMapToolsEditorPath -Name 'code' -LocalAppData 'C:\Local' -ProgramFiles 'C:\Program Files')
        $paths -contains 'C:\Local\Programs\Microsoft VS Code\bin\code.cmd' | Should -BeTrue
        $paths -contains 'C:\Program Files\Microsoft VS Code\bin\code.cmd' | Should -BeTrue

        $insiders = @(Get-QBuildMapToolsEditorPath -Name 'code-insiders' -LocalAppData 'C:\Local' -ProgramFiles 'C:\Program Files')
        $insiders -contains 'C:\Program Files\Microsoft VS Code Insiders\bin\code-insiders.cmd' | Should -BeTrue

        $cursor = @(Get-QBuildMapToolsEditorPath -Name 'cursor' -LocalAppData 'C:\Local' -ProgramFiles 'C:\Program Files')
        $cursor -contains 'C:\Local\Programs\cursor\resources\app\bin\cursor.cmd' | Should -BeTrue
    }

    It 'uses a PATH command and skips Windows app execution aliases' {
        $resolved = Resolve-QBuildMapToolsEditor -Editor 'code' -LocalAppData 'C:\Local' -ProgramFiles 'C:\Program Files' -GetCommand {
            param($Name)
            if ($Name -eq 'code') { 'C:\Users\me\AppData\Local\Microsoft\WindowsApps\code.exe' }
        } -TestEditorPath {
            param($Path)
            $Path -eq 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
        }

        $resolved.Name | Should -Be 'code'
        $resolved.Command | Should -Be 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
    }

    It 'resolves every detected editor when no editor is requested' {
        $resolved = @(Resolve-QBuildMapToolsEditor -GetCommand {
                param($Name)
                switch ($Name) {
                    'code' { 'C:\vscode\bin\code.cmd' }
                    'cursor' { 'C:\cursor\cursor.cmd' }
                }
            } -TestEditorPath { $false })

        ($resolved.Name -join ',') | Should -Be 'code,cursor'
    }

    It 'fails when the requested editor is not installed' {
        { Resolve-QBuildMapToolsEditor -Editor 'cursor' -GetCommand { $null } -TestEditorPath { $false } } |
            Should -Throw "*Editor 'cursor' was not found*"
    }

    It 'downloads the selected VSIX and installs it into each editor' {
        $script:savedUrl = $null
        $script:installed = @()
        $script:vsixPath = $null

        Install-QBuildMapTools -GetRelease {
            [pscustomobject]@{
                Version     = [version]'0.1.1'
                Tag         = 'qbuild-map-tools-v0.1.1'
                AssetName   = 'qbuild-map-tools-0.1.1.vsix'
                DownloadUrl = 'https://example.test/qbuild-map-tools-0.1.1.vsix'
            }
        } -ResolveEditor {
            @(
                [pscustomobject]@{ Name = 'code'; Command = 'C:\vscode\bin\code.cmd' }
                [pscustomobject]@{ Name = 'cursor'; Command = 'C:\cursor\cursor.cmd' }
            )
        } -SaveAsset {
            param($Url, $Destination)
            $script:savedUrl = $Url
            $script:vsixPath = $Destination
            Set-Content -LiteralPath $Destination -Value 'vsix'
        } -InstallExtension {
            param($Command, $VsixPath)
            $script:installed += $Command
            Test-Path -LiteralPath $VsixPath | Should -BeTrue
        }

        $script:savedUrl | Should -Be 'https://example.test/qbuild-map-tools-0.1.1.vsix'
        ($script:installed -join ',') | Should -Be 'C:\vscode\bin\code.cmd,C:\cursor\cursor.cmd'
        Test-Path -LiteralPath $script:vsixPath | Should -BeFalse
    }

    It 'removes the downloaded VSIX when installation fails' {
        $script:vsixPath = $null
        {
            Install-QBuildMapTools -GetRelease {
                [pscustomobject]@{
                    Version     = [version]'0.1.1'
                    Tag         = 'qbuild-map-tools-v0.1.1'
                    AssetName   = 'qbuild-map-tools-0.1.1.vsix'
                    DownloadUrl = 'https://example.test/qbuild-map-tools-0.1.1.vsix'
                }
            } -ResolveEditor {
                [pscustomobject]@{ Name = 'code'; Command = 'code.cmd' }
            } -SaveAsset {
                param($Url, $Destination)
                $script:vsixPath = $Destination
                Set-Content -LiteralPath $Destination -Value 'vsix'
            } -InstallExtension {
                throw 'install failed'
            }
        } | Should -Throw '*install failed*'

        Test-Path -LiteralPath $script:vsixPath | Should -BeFalse
    }

    It 'honors QBUILD_EDITOR and QBUILD_MAP_TOOLS_VERSION when parameters are omitted' {
        $env:QBUILD_EDITOR = 'cursor'
        $env:QBUILD_MAP_TOOLS_VERSION = '0.1.1'
        $script:seen = $null
        try {
            Install-QBuildMapTools -GetRelease {
                param($RequestedVersion)
                $script:seen = $RequestedVersion
                [pscustomobject]@{
                    Version     = [version]'0.1.1'
                    Tag         = 'qbuild-map-tools-v0.1.1'
                    AssetName   = 'qbuild-map-tools-0.1.1.vsix'
                    DownloadUrl = 'https://example.test/qbuild-map-tools-0.1.1.vsix'
                }
            } -ResolveEditor {
                param($Name)
                $script:seen = "$script:seen|$Name"
                [pscustomobject]@{ Name = $Name; Command = "$Name.cmd" }
            } -SaveAsset {
                param($Url, $Destination)
                Set-Content -LiteralPath $Destination -Value 'vsix'
            } -InstallExtension { }

            $script:seen | Should -Be '0.1.1|cursor'
        }
        finally {
            $env:QBUILD_EDITOR = $null
            $env:QBUILD_MAP_TOOLS_VERSION = $null
        }
    }
}
