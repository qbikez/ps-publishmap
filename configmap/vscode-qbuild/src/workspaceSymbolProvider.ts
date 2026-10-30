import * as vscode from "vscode";
import { parseMap, TextSpan } from "./mapParser";
import {
  getQbuildSymbols,
  matchQbuildSymbols,
  QbuildSymbol,
} from "./symbolModel";

const buildMapGlob = "**/.build.map.ps1";

function toRange(document: vscode.TextDocument, span: TextSpan): vscode.Range {
  return new vscode.Range(
    document.positionAt(span.start),
    document.positionAt(span.end),
  );
}

function toWorkspaceSymbol(
  document: vscode.TextDocument,
  symbol: QbuildSymbol,
): vscode.SymbolInformation {
  const container =
    vscode.workspace.asRelativePath(document.uri, false) ||
    document.fileName;

  return new vscode.SymbolInformation(
    symbol.detail,
    symbol.kind === "command"
      ? vscode.SymbolKind.Function
      : vscode.SymbolKind.Namespace,
    container,
    new vscode.Location(document.uri, toRange(document, symbol.selectionSpan)),
  );
}

async function readMapDocument(
  uri: vscode.Uri,
): Promise<vscode.TextDocument | undefined> {
  const open = vscode.workspace.textDocuments.find(
    (document) => document.uri.toString() === uri.toString(),
  );
  if (open) {
    return open;
  }

  try {
    return await vscode.workspace.openTextDocument(uri);
  } catch {
    return undefined;
  }
}

export class QbuildWorkspaceSymbolProvider
  implements vscode.WorkspaceSymbolProvider
{
  async provideWorkspaceSymbols(
    query: string,
  ): Promise<vscode.SymbolInformation[]> {
    const files = await vscode.workspace.findFiles(
      buildMapGlob,
      "**/node_modules/**",
    );
    const results: vscode.SymbolInformation[] = [];

    for (const uri of files) {
      const document = await readMapDocument(uri);
      if (!document) {
        continue;
      }

      const symbols = matchQbuildSymbols(
        getQbuildSymbols(parseMap(document.getText())),
        query,
      );
      for (const symbol of symbols) {
        results.push(toWorkspaceSymbol(document, symbol));
      }
    }

    return results;
  }
}
