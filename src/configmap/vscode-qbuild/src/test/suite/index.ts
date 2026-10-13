import assert from "node:assert/strict";
import * as path from "node:path";
import * as vscode from "vscode";

export async function run(): Promise<void> {
  const extension = vscode.extensions.getExtension("hmdev.qbuild-map-tools");
  assert.ok(extension, "Development extension was not loaded");
  await extension.activate();

  const folders = vscode.workspace.workspaceFolders;
  assert.ok(folders && folders.length > 0, "Expected a test workspace folder");
  const mapPath = path.join(folders[0].uri.fsPath, ".build.map.ps1");

  try {
    let document = await vscode.workspace.openTextDocument(mapPath);
    document = await vscode.languages.setTextDocumentLanguage(
      document,
      "powershell",
    );

    const symbols = await vscode.commands.executeCommand<
      vscode.DocumentSymbol[]
    >("vscode.executeDocumentSymbolProvider", document.uri);
    assert.ok(symbols);
    assert.deepEqual(
      symbols.map((symbol) => symbol.name),
      ["frontend"],
    );
    assert.deepEqual(
      symbols[0].children.map((symbol) => symbol.name),
      ["build"],
    );

    const source = document.getText();
    const settingsOffset = source.indexOf("    \n", source.indexOf("_settings"));
    const completions = await vscode.commands.executeCommand<
      vscode.CompletionList
    >(
      "vscode.executeCompletionItemProvider",
      document.uri,
      document.positionAt(settingsOffset + 4),
    );
    assert.ok(completions.items.some((item) => item.label === "Debug"));
    assert.ok(completions.items.some((item) => item.label === "Process"));

    const workspaceSymbols = await vscode.commands.executeCommand<
      vscode.SymbolInformation[]
    >("vscode.executeWorkspaceSymbolProvider", "frontend");
    assert.ok(workspaceSymbols);
    assert.ok(
      workspaceSymbols.some((symbol) => symbol.name === "frontend.build"),
      `Expected frontend.build in ${workspaceSymbols.map((s) => s.name).join(", ")}`,
    );
  } finally {
    await vscode.commands.executeCommand("workbench.action.closeAllEditors");
  }
}
