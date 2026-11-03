# qbuild Map Tools

VS Code navigation and completion for qbuild `.build.map.ps1` files.

## Features

- Completes qbuild metadata such as `_settings`, `exec`, `description`, `list`, `#include`, and `_dependsOn`.
- Completes supported keys inside `_settings` and `prefix` inside include configuration.
- Adds nested map entries to Breadcrumbs, Outline, Go to Symbol in Editor, and Go to Symbol in Workspace (`Ctrl+T`).
- Parses map text without executing it.

The extension does not register a language or grammar. Build maps remain PowerShell documents, so the normal PowerShell extension continues to provide highlighting, formatting, diagnostics, debugging, and general PowerShell IntelliSense.

## Install

Install the latest published release into every detected editor (`code`, `cursor`, and `code-insiders`):

```powershell
iwr -UseBasicParsing https://raw.githubusercontent.com/qbikez/ps-publishmap/master/configmap/vscode-qbuild/install.ps1 | iex
```

Reload the editor window after the script finishes.

Set `QBUILD_EDITOR` to `code`, `cursor`, or `code-insiders` to install into one editor. Set `QBUILD_MAP_TOOLS_VERSION` to a `major.minor.patch` version to pin a release:

```powershell
$env:QBUILD_EDITOR = 'cursor'
$env:QBUILD_MAP_TOOLS_VERSION = '0.1.1'
iwr -UseBasicParsing https://raw.githubusercontent.com/qbikez/ps-publishmap/master/configmap/vscode-qbuild/install.ps1 | iex
```

Running the script file uses the same variables:

```powershell
./install.ps1
```

Dot-source it when you want to pass parameters to `Install-QBuildMapTools`:

```powershell
. ./install.ps1
Install-QBuildMapTools -Editor cursor -Version 0.1.1
```

Published VSIX packages are attached to GitHub releases tagged `qbuild-map-tools-v<version>`.

## Development

```powershell
npm install
npm test
```

Open this directory in VS Code and press `F5` to start an Extension Development Host. Open a file named `.build.map.ps1`, keep its language mode set to PowerShell, and use `Ctrl+Space` inside a map hashtable to request completion.

## Packaging

```powershell
npm run package
```

The packaged extension is written to `.publish/`. Install that `.vsix` with **Extensions: Install from VSIX...**, or run `qbuild install` from this directory.

`package` and `install` do not change the version.

## Releasing

`qbuild release` is the only command that publishes the extension. It bumps the version, runs the unit tests, packages `.publish/qbuild-map-tools-<version>.vsix`, commits that version, pushes the current branch, and creates a GitHub release tagged `qbuild-map-tools-v<version>` with the VSIX attached. The tag is namespaced so it stays separate from publishmap module tags.

Bump patch for fixes, minor for features, and major for breaking changes. Use `current` to publish the version already in `package.json` without bumping it, including the first release of `0.1.0`.

```powershell
qbuild release
qbuild release -Part minor
qbuild release -Part major
qbuild release -Part current -Notes "First extension release"
```

Commit changes under `vscode-qbuild` before releasing. The command requires `gh` to be authenticated and pushes the current branch.
