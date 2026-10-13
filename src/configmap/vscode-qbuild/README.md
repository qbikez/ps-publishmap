# qbuild Map Tools

VS Code navigation and completion for qbuild `.build.map.ps1` files.

## Features

- Completes qbuild metadata such as `_settings`, `exec`, `description`, `list`, `#include`, and `_dependsOn`.
- Completes supported keys inside `_settings` and `prefix` inside include configuration.
- Adds nested map entries to Breadcrumbs, Outline, Go to Symbol in Editor, and Go to Symbol in Workspace (`Ctrl+T`).
- Parses map text without executing it.

The extension does not register a language or grammar. Build maps remain PowerShell documents, so the normal PowerShell extension continues to provide highlighting, formatting, diagnostics, debugging, and general PowerShell IntelliSense.

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

The generated `.vsix` can be installed with **Extensions: Install from VSIX...**.
