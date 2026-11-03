import { MapMember, MapTable, ParsedMap, TextSpan } from "./mapParser";

export type QbuildSymbolKind = "command" | "group";

export interface QbuildSymbol {
  name: string;
  detail: string;
  kind: QbuildSymbolKind;
  span: TextSpan;
  selectionSpan: TextSpan;
  children: QbuildSymbol[];
}

const reservedKeys = new Set([
  "exec",
  "list",
  "options",
  "#include",
  "_basedir",
  "_sourcefile",
  "_settings",
  "_dependson",
  "_internal",
  "description",
  "validate",
  "get",
  "set",
]);

function isReserved(key: string): boolean {
  return reservedKeys.has(key.toLowerCase());
}

function membersFromTable(
  table: MapTable,
  parentPath: string,
): QbuildSymbol[] {
  const symbols: QbuildSymbol[] = [];

  for (const member of table.members) {
    if (member.key.toLowerCase() === "list" && member.table) {
      symbols.push(...membersFromTable(member.table, parentPath));
      continue;
    }
    if (isReserved(member.key)) continue;
    if (member.valueKind !== "scriptblock" && !member.table) continue;

    symbols.push(symbolFromMember(member, parentPath));
  }

  return symbols;
}

function symbolFromMember(member: MapMember, parentPath: string): QbuildSymbol {
  const path = parentPath ? `${parentPath}.${member.key}` : member.key;
  const children = member.table
    ? membersFromTable(member.table, path)
    : [];
  const hasExec =
    member.table?.members.some(
      (child) => child.key.toLowerCase() === "exec",
    ) ?? false;

  return {
    name: member.key,
    detail: path,
    kind: member.valueKind === "scriptblock" || hasExec ? "command" : "group",
    span: member.span,
    selectionSpan: member.keySpan,
    children,
  };
}

export function getQbuildSymbols(parsed: ParsedMap): QbuildSymbol[] {
  return parsed.tables.flatMap((table) => membersFromTable(table, ""));
}

export function flattenQbuildSymbols(
  symbols: QbuildSymbol[],
): QbuildSymbol[] {
  const flattened: QbuildSymbol[] = [];

  for (const symbol of symbols) {
    flattened.push(symbol);
    flattened.push(...flattenQbuildSymbols(symbol.children));
  }

  return flattened;
}

export function matchQbuildSymbols(
  symbols: QbuildSymbol[],
  query: string,
): QbuildSymbol[] {
  const flattened = flattenQbuildSymbols(symbols);
  const needle = query.trim().toLowerCase();
  if (!needle) {
    return flattened;
  }

  return flattened.filter(
    (symbol) =>
      symbol.name.toLowerCase().includes(needle) ||
      symbol.detail.toLowerCase().includes(needle),
  );
}
