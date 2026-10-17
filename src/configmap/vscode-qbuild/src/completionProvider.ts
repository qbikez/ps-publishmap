import * as vscode from "vscode";
import { getCompletionSuggestions } from "./completionModel";
import { parseMap } from "./mapParser";

function replacementRange(
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
    );
    const range = replacementRange(document, position);

    return suggestions.map((suggestion) => {
      const item = new vscode.CompletionItem(
        suggestion.label,
        vscode.CompletionItemKind.Property,
      );
      item.detail = suggestion.detail;
      item.range = range;
      item.insertText = suggestion.isSnippet
        ? new vscode.SnippetString(suggestion.insertText)
        : suggestion.insertText;
      return item;
    });
  }
}
