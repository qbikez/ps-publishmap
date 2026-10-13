import assert from "node:assert/strict";
import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import * as vscode from "vscode";

export async function run(): Promise<void> {
  const extension = vscode.extensions.getExtension("hmdev.qbuild-map-tools");
  assert.ok(extension, "Development extension was not loaded");
  await extension.activate();

  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "qbuild-vscode-"));
  const mapPath = path.join(directory, ".build.map.ps1");
  const source = `@{
  _settings = @{
    
  }
  frontend = @{
    build = { 'build' }
  }
}`;
  await fs.writeFile(mapPath, source, "utf8");

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
  } finally {
    await vscode.commands.executeCommand("workbench.action.closeAllEditors");
    await fs.rm(directory, { recursive: true, force: true });
  }
}
