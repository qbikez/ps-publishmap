import * as vscode from "vscode";
import { QbuildCompletionProvider } from "./completionProvider";
import { QbuildDocumentSymbolProvider } from "./symbolProvider";
import { QbuildWorkspaceSymbolProvider } from "./workspaceSymbolProvider";

const buildMapSelector: vscode.DocumentSelector = {
  language: "powershell",
  pattern: "**/.build.map.ps1",
  scheme: "file",
};

export function activate(context: vscode.ExtensionContext): void {
  context.subscriptions.push(
    vscode.languages.registerCompletionItemProvider(
      buildMapSelector,
      new QbuildCompletionProvider(),
      "_",
      "'",
    ),
    vscode.languages.registerDocumentSymbolProvider(
      buildMapSelector,
      new QbuildDocumentSymbolProvider(),
      {
        label: "qbuild map entries",
      },
    ),
    vscode.languages.registerWorkspaceSymbolProvider(
      new QbuildWorkspaceSymbolProvider(),
    ),
  );
}

export function deactivate(): void {}
