# Build qbuild VS Code extension

## Extension scaffold

- Create `vscode-qbuild/package.json`, `vscode-qbuild/tsconfig.json`, and `vscode-qbuild/src/extension.ts` with a PowerShell document selector restricted to `**/.build.map.ps1`.
- Add build, test, and package scripts, extension metadata, a README, and VSIX exclusions so the extension can be run and packaged independently.
- Keep `.build.map.ps1` documents registered as PowerShell. The extension augments the existing PowerShell editor features and does not contribute a language or grammar.

## Safe map structure parser

- Implement a non-evaluating PowerShell-aware tokenizer/parser in `vscode-qbuild/src/mapParser.ts` that recognizes hashtable keys, `@{}` and `[ordered]@{}` nesting, scriptblock values, comments, and quoted strings.
- Represent nested qbuild entries and metadata with source ranges; never dot-source or execute a map while editing it.

## Context-aware completion

- Add a completion provider in `vscode-qbuild/src/completionProvider.ts` for valid hashtable key positions.
- Suggest qbuild metadata (`_settings`, `exec`, `description`, `list`, `#include`, `_dependsOn`) with useful insertion snippets.
- Inside `_settings`, suggest `Debug`, `Concurrently`, `TmuxAutoWindow`, `DiscoveryCache`, `DiscoveryCacheLocation`, and `Process`, including known values where applicable.
- Handle include configuration context (`prefix`) and suppress already-present keys and suggestions inside scripts, strings, and comments.

## Native navigation

- Add a hierarchical `DocumentSymbolProvider` in `vscode-qbuild/src/symbolProvider.ts`.
- Emit command and group entries with full dotted paths as symbol details while excluding reserved metadata, so native Breadcrumbs, Outline, and Go to Symbol navigate nested maps.
- Support direct nesting and `list = @{ ... }`.

## Verification

- Add focused parser/provider tests and representative fixtures under `vscode-qbuild/src/test`.
- Cover direct and ordered maps, nested/list entries, quoted keys, comments and strings containing braces, malformed in-progress input, completion contexts, duplicate suppression, and symbol ranges.
- Run compilation and tests, and document local launch and VSIX packaging commands in `vscode-qbuild/README.md`.
