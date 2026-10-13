<#
.SYNOPSIS
    Install the qbuild Map Tools extension from GitHub releases.

.DESCRIPTION
    Downloads the VSIX for a qbuild-map-tools release and installs it with the
    VS Code, Cursor, or VS Code Insiders CLI.

    Pipe the script to Invoke-Expression:

        iwr -UseBasicParsing https://raw.githubusercontent.com/qbikez/ps-publishmap/master/src/configmap/vscode-qbuild/install.ps1 | iex

    Set QBUILD_EDITOR to code, cursor, or code-insiders to install into one editor.
    Set QBUILD_MAP_TOOLS_VERSION to a major.minor.patch version to pin a release.
    When those variables are empty, the latest release is installed into every detected editor.

.EXAMPLE
    iwr -UseBasicParsing https://raw.githubusercontent.com/qbikez/ps-publishmap/master/src/configmap/vscode-qbuild/install.ps1 | iex

.EXAMPLE
    $env:QBUILD_EDITOR = 'cursor'
    $env:QBUILD_MAP_TOOLS_VERSION = '0.1.1'
    ./install.ps1

.EXAMPLE
    . ./install.ps1
    Install-QBuildMapTools -Editor cursor -Version 0.1.1
#>

function Get-QBuildMapToolsNextLink {
    param($Link)

    $text = @($Link | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ','
    if ($text -match '<(?<url>[^>]+)>;\s*rel="next"') {
        return $Matches.url
    }
    return $null
}

function Select-QBuildMapToolsTag {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Refs = @(),
        [string]$Version
    )

    if (-not [string]::IsNullOrWhiteSpace($Version) -and $Version -notmatch '^\d+\.\d+\.\d+$') {
        throw "Version '$Version' must be major.minor.patch."
    }

    $parsed = @(
        foreach ($ref in @($Refs)) {
            $name = [string]$ref.ref
            if ($name -match '^refs/tags/qbuild-map-tools-v(?<version>\d+\.\d+\.\d+)$') {
                [pscustomobject]@{
                    Tag     = "qbuild-map-tools-v$($Matches.version)"
                    Version = [version]$Matches.version
                }
            }
        }
    )

    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $match = $parsed | Where-Object { $_.Version -eq [version]$Version } | Select-Object -First 1
        if ($null -eq $match) {
            $published = @($parsed | Sort-Object Version -Descending | ForEach-Object { $_.Version.ToString() })
            $available = if ($published.Count -eq 0) { 'none' } else { $published -join ', ' }
            throw "qbuild Map Tools version '$Version' was not found. Published versions: $available."
        }
        return $match
    }

    $selected = $parsed | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -eq $selected) {
        throw 'No qbuild Map Tools release was found.'
    }
    return $selected
}

function Select-QBuildMapToolsAsset {
    param($Release)

    $tag = [string]$Release.tag_name
    if ($tag -notmatch '^qbuild-map-tools-v(?<version>\d+\.\d+\.\d+)$') {
        throw "Release tag '$tag' is not a qbuild Map Tools release."
    }

    $version = [version]$Matches.version
    $asset = @($Release.assets) | Where-Object { $_.name -like '*.vsix' } | Select-Object -First 1
    if ($null -eq $asset -or [string]::IsNullOrWhiteSpace([string]$asset.browser_download_url)) {
        throw "Release '$tag' does not include a VSIX asset."
    }

    [pscustomobject]@{
        Version     = $version
        Tag         = $tag
        AssetName   = [string]$asset.name
        DownloadUrl = [string]$asset.browser_download_url
    }
}

function Get-QBuildMapToolsEditorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$ProgramFiles = $env:ProgramFiles
    )

    $relative = switch ($Name) {
        'code' {
            @(
                @{ Root = $LocalAppData; Relative = 'Programs\Microsoft VS Code\bin\code.cmd' }
                @{ Root = $ProgramFiles; Relative = 'Microsoft VS Code\bin\code.cmd' }
            )
        }
        'code-insiders' {
            @(
                @{ Root = $LocalAppData; Relative = 'Programs\Microsoft VS Code Insiders\bin\code-insiders.cmd' }
                @{ Root = $ProgramFiles; Relative = 'Microsoft VS Code Insiders\bin\code-insiders.cmd' }
            )
        }
        'cursor' {
            @(
                @{ Root = $LocalAppData; Relative = 'Programs\cursor\resources\app\bin\cursor.cmd' }
                @{ Root = $LocalAppData; Relative = 'Programs\Cursor\resources\app\bin\cursor.cmd' }
            )
        }
        default {
            throw "Unknown editor '$Name'. Use code, cursor, or code-insiders."
        }
    }

    foreach ($entry in $relative) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.Root)) {
            Join-Path -Path $entry.Root -ChildPath $entry.Relative
        }
    }
}

function Resolve-QBuildMapToolsEditor {
    [CmdletBinding()]
    param(
        [string]$Editor,
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$ProgramFiles = $env:ProgramFiles,
        [scriptblock]$GetCommand = {
            param($Name)
            $command = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $command) {
                return $null
            }
            return $command.Source
        },
        [scriptblock]$TestEditorPath = {
            param($Path)
            if ([string]::IsNullOrWhiteSpace($Path)) {
                return $false
            }
            Test-Path -LiteralPath $Path
        }
    )

    $allowed = @('code', 'cursor', 'code-insiders')
    $names = if ([string]::IsNullOrWhiteSpace($Editor)) { $allowed } else { @($Editor) }
    $resolved = @(
        foreach ($name in $names) {
            if ($name -notin $allowed) {
                throw "Unknown editor '$name'. Use code, cursor, or code-insiders."
            }

            $command = & $GetCommand $name
            if ($command -and $command -notmatch '(?i)\\WindowsApps\\') {
                [pscustomobject]@{
                    Name    = $name
                    Command = [string]$command
                }
                continue
            }

            $path = @(Get-QBuildMapToolsEditorPath -Name $name -LocalAppData $LocalAppData -ProgramFiles $ProgramFiles) |
                Where-Object { & $TestEditorPath $_ } |
                Select-Object -First 1
            if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
                [pscustomobject]@{
                    Name    = $name
                    Command = [string]$path
                }
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($Editor)) {
                throw "Editor '$name' was not found. Install the '$name' shell command from the Command Palette, then run this script again."
            }
        }
    )

    if ($resolved.Count -eq 0) {
        throw "No editor CLI was found. Install the 'code', 'cursor', or 'code-insiders' command from the Command Palette, then run this script again."
    }

    return $resolved
}

function Invoke-QBuildMapToolsGitHubGet {
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $protocols = [Net.ServicePointManager]::SecurityProtocol
        if (($protocols -band [Net.SecurityProtocolType]::Tls12) -eq 0) {
            [Net.ServicePointManager]::SecurityProtocol = $protocols -bor [Net.SecurityProtocolType]::Tls12
        }
    }

    $headers = @{
        Accept                 = 'application/vnd.github+json'
        'User-Agent'           = 'qbuild-map-tools-install'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    try {
        return Invoke-WebRequest -Uri $Uri -Headers $headers -UseBasicParsing
    }
    catch {
        $status = $null
        $response = $_.Exception.Response
        if ($null -ne $response) {
            $status = [int]$response.StatusCode
        }

        if ($status -eq 404) {
            return $null
        }
        if ($status -eq 403) {
            throw "GitHub API rate limit was reached while looking up qbuild Map Tools. Download a VSIX from https://github.com/qbikez/ps-publishmap/releases and install it with: code --install-extension <file>.vsix"
        }
        throw
    }
}

function Get-QBuildMapToolsTagRef {
    $uri = 'https://api.github.com/repos/qbikez/ps-publishmap/git/matching-refs/tags/qbuild-map-tools-v?per_page=100'
    $refs = @()
    for ($page = 0; $uri -and $page -lt 10; $page++) {
        $response = Invoke-QBuildMapToolsGitHubGet -Uri $uri
        if ($null -eq $response) {
            break
        }

        $parsed = $response.Content | ConvertFrom-Json
        if ($null -ne $parsed) {
            $refs += @($parsed)
        }
        $uri = Get-QBuildMapToolsNextLink -Link $response.Headers['Link']
    }
    return $refs
}

function Get-QBuildMapToolsRelease {
    param([string]$Version)

    $tag = Select-QBuildMapToolsTag -Refs @(Get-QBuildMapToolsTagRef) -Version $Version
    $response = Invoke-QBuildMapToolsGitHubGet -Uri "https://api.github.com/repos/qbikez/ps-publishmap/releases/tags/$($tag.Tag)"
    if ($null -eq $response) {
        throw "GitHub release '$($tag.Tag)' was not found."
    }

    return Select-QBuildMapToolsAsset -Release ($response.Content | ConvertFrom-Json)
}

function Install-QBuildMapTools {
    <#
    .SYNOPSIS
        Download a qbuild Map Tools release and install its VSIX.

    .PARAMETER Version
        Extension version to install, such as 0.1.1. Defaults to QBUILD_MAP_TOOLS_VERSION, then to the latest release.

    .PARAMETER Editor
        Editor CLI to install into: code, cursor, or code-insiders.
        Defaults to QBUILD_EDITOR, then to every detected editor.
    #>
    [CmdletBinding()]
    param(
        [string]$Version,
        [string]$Editor,
        [scriptblock]$GetRelease = {
            param($RequestedVersion)
            Get-QBuildMapToolsRelease -Version $RequestedVersion
        },
        [scriptblock]$ResolveEditor = {
            param($Name)
            Resolve-QBuildMapToolsEditor -Editor $Name
        },
        [scriptblock]$SaveAsset = {
            param($Url, $Destination)
            Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        },
        [scriptblock]$InstallExtension = {
            param($Command, $VsixPath)
            & $Command --install-extension $VsixPath --force
            if ($LASTEXITCODE -ne 0) {
                throw "Installing '$VsixPath' with '$Command' failed."
            }
        }
    )

    if ([string]::IsNullOrWhiteSpace($Version) -and -not [string]::IsNullOrWhiteSpace($env:QBUILD_MAP_TOOLS_VERSION)) {
        $Version = $env:QBUILD_MAP_TOOLS_VERSION
    }
    if ([string]::IsNullOrWhiteSpace($Editor) -and -not [string]::IsNullOrWhiteSpace($env:QBUILD_EDITOR)) {
        $Editor = $env:QBUILD_EDITOR
    }

    $destination = $null
    $previousProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        $release = & $GetRelease $Version
        $editors = @(& $ResolveEditor $Editor)
        if ($editors.Count -eq 0 -or $null -eq $editors[0]) {
            throw "No editor CLI was found. Install the 'code', 'cursor', or 'code-insiders' command from the Command Palette, then run this script again."
        }

        $destination = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $release.AssetName
        Write-Host "Downloading qbuild Map Tools $($release.Version)..."
        & $SaveAsset $release.DownloadUrl $destination
        foreach ($item in $editors) {
            Write-Host "Installing $($release.AssetName) with $($item.Name)..."
            & $InstallExtension $item.Command $destination
            Write-Host "Installed qbuild Map Tools $($release.Version) with $($item.Name). Reload the editor to use it." -ForegroundColor Green
        }
    }
    finally {
        $ProgressPreference = $previousProgress
        if ($null -ne $destination -and (Test-Path -LiteralPath $destination)) {
            Remove-Item -LiteralPath $destination -Force
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $installerFunctions = @(
        'Get-QBuildMapToolsNextLink'
        'Select-QBuildMapToolsTag'
        'Select-QBuildMapToolsAsset'
        'Get-QBuildMapToolsEditorPath'
        'Resolve-QBuildMapToolsEditor'
        'Invoke-QBuildMapToolsGitHubGet'
        'Get-QBuildMapToolsTagRef'
        'Get-QBuildMapToolsRelease'
        'Install-QBuildMapTools'
    )
    try {
        Install-QBuildMapTools
    }
    finally {
        if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
            foreach ($name in $installerFunctions) {
                Remove-Item -LiteralPath "Function:\$name" -ErrorAction SilentlyContinue
            }
        }
    }
}
