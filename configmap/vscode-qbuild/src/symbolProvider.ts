import * as vscode from "vscode";
import { parseMap, TextSpan } from "./mapParser";
import { getQbuildSymbols, QbuildSymbol } from "./symbolModel";

function toRange(document: vscode.TextDocument, span: TextSpan): vscode.Range {
  return new vscode.Range(
    document.positionAt(span.start),
    document.positionAt(span.end),
  );
}

function toDocumentSymbol(
  document: vscode.TextDocument,
  symbol: QbuildSymbol,
): vscode.DocumentSymbol {
  const documentSymbol = new vscode.DocumentSymbol(
    symbol.name,
    symbol.detail,
    symbol.kind === "command"
      ? vscode.SymbolKind.Function
      : vscode.SymbolKind.Namespace,
    toRange(document, symbol.span),
    toRange(document, symbol.selectionSpan),
  );
  documentSymbol.children = symbol.children.map((child) =>
    toDocumentSymbol(document, child),
  );
  return documentSymbol;
}

export class QbuildDocumentSymbolProvider
  implements vscode.DocumentSymbolProvider
{
  provideDocumentSymbols(
    document: vscode.TextDocument,
  ): vscode.DocumentSymbol[] {
    const parsed = parseMap(document.getText());
    return getQbuildSymbols(parsed).map((symbol) =>
      toDocumentSymbol(document, symbol),
    );
  }
}
