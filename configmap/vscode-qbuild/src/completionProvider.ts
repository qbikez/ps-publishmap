import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { getCompletionSuggestions } from "./completionModel";
import { parseMap } from "./mapParser";

const skippedDirectories = new Set([
  ".git",
  "node_modules",
  "bin",
  "obj",
  "out",
  "dist",
]);
const maxFileDepth = 3;
const maxFiles = 500;

/** Files under `root`, relative and `/`-separated, for `_template` path completion. */
function listFilesNear(root: string): string[] {
  const files: string[] = [];
  const visit = (directory: string, relative: string, depth: number) => {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(directory, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (files.length >= maxFiles) return;
      const child = relative ? `${relative}/${entry.name}` : entry.name;
      if (entry.isFile()) {
        files.push(child);
      } else if (
        entry.isDirectory() &&
        depth < maxFileDepth &&
        !skippedDirectories.has(entry.name)
      ) {
        visit(path.join(directory, entry.name), child, depth + 1);
      }
    }
  };
  visit(root, "", 1);
  return files;
}

function wordRange(
  document: vscode.TextDocument,
  position: vscode.Position,
): vscode.Range {
  const linePrefix = document
    .lineAt(position.line)
    .text.slice(0, position.character);
  const match = linePrefix.match(/['"]?[$#\w-]*$/);
  const length = match?.[0].length ?? 0;
  return new vscode.Range(
    position.translate(0, -length),
    position,
  );
}

export class QbuildCompletionProvider
  implements vscode.CompletionItemProvider
{
  provideCompletionItems(
    document: vscode.TextDocument,
    position: vscode.Position,
  ): vscode.CompletionItem[] {
    const parsed = parseMap(document.getText());
    const suggestions = getCompletionSuggestions(
      parsed,
      document.offsetAt(position),
      { listFiles: () => listFilesNear(path.dirname(document.uri.fsPath)) },
    );
    const range = wordRange(document, position);

    return suggestions.map((suggestion) => {
      const item = new vscode.CompletionItem(
        suggestion.label,
        vscode.CompletionItemKind.Property,
      );
      item.detail = suggestion.detail;
      item.range =
        suggestion.replaceStart === undefined
          ? range
          : new vscode.Range(
              document.positionAt(suggestion.replaceStart),
              position,
            );
      item.insertText = suggestion.isSnippet
        ? new vscode.SnippetString(suggestion.insertText)
        : suggestion.insertText;
      if (suggestion.retrigger) {
        item.command = {
          command: "editor.action.triggerSuggest",
          title: "Suggest",
        };
      }
      return item;
    });
  }
}
