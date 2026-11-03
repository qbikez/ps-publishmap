import {
  findTableAtOffset,
  isIgnoredOffset,
  MapTable,
  ParsedMap,
} from "./mapParser";

export interface CompletionSuggestion {
  label: string;
  detail: string;
  insertText: string;
  isSnippet?: boolean;
}

const mapSuggestions: CompletionSuggestion[] = [
  {
    label: "_settings",
    detail: "qbuild settings inherited by this entry",
    insertText: "_settings = @{ ${1} }",
    isSnippet: true,
  },
  {
    label: "exec",
    detail: "Script or child entries executed by this entry",
    insertText: "exec = {\n\t${0}\n}",
    isSnippet: true,
  },
  {
    label: "description",
    detail: "Description shown by qbuild help and list",
    insertText: "description = '${1:Description}'",
    isSnippet: true,
  },
  {
    label: "list",
    detail: "Explicit nested entry container",
    insertText: "list = @{\n\t${0}\n}",
    isSnippet: true,
  },
  {
    label: "#include",
    detail: "Include entries from another build map",
    insertText: "'#include' = @{\n\t${0}\n}",
    isSnippet: true,
  },
  {
    label: "_dependsOn",
    detail: "Discovery-cache file dependencies",
    insertText: "_dependsOn = @('${1:path}')",
    isSnippet: true,
  },
];

const settingSuggestions: CompletionSuggestion[] = [
  {
    label: "Debug",
    detail: "Enable ConfigMap debug behavior",
    insertText: "Debug = $false",
  },
  {
    label: "Concurrently",
    detail: "Run eligible child entries concurrently",
    insertText: "Concurrently = $false",
  },
  {
    label: "TmuxAutoWindow",
    detail: "Create tmux windows automatically",
    insertText: "TmuxAutoWindow = $false",
  },
  {
    label: "DiscoveryCache",
    detail: "Enable qbuild command discovery cache",
    insertText: "DiscoveryCache = $true",
  },
  {
    label: "DiscoveryCacheLocation",
    detail: "Select local or user discovery cache storage",
    insertText: "DiscoveryCacheLocation = '${1|local,user|}'",
    isSnippet: true,
  },
  {
    label: "Process",
    detail: "Select the qbuild or qrun entry processor",
    insertText: "Process = '${1|qbuild,qrun|}'",
    isSnippet: true,
  },
];

const includeSuggestions: CompletionSuggestion[] = [
  {
    label: "prefix",
    detail: "Prefix included entries with the include name",
    insertText: "prefix = $true",
  },
];

const booleanValueSuggestions: CompletionSuggestion[] = [
  { label: "$true", detail: "PowerShell true", insertText: "$true" },
  { label: "$false", detail: "PowerShell false", insertText: "$false" },
];

const settingValues: Record<string, CompletionSuggestion[]> = {
  debug: booleanValueSuggestions,
  concurrently: booleanValueSuggestions,
  tmuxautowindow: booleanValueSuggestions,
  discoverycache: booleanValueSuggestions,
  discoverycachelocation: [
    { label: "local", detail: "Project-local cache", insertText: "'local'" },
    { label: "user", detail: "Per-user cache", insertText: "'user'" },
  ],
  process: [
    { label: "qbuild", detail: "Standard qbuild command", insertText: "'qbuild'" },
    { label: "qrun", detail: "Durable multi-step process", insertText: "'qrun'" },
  ],
};

function hasKey(table: MapTable, key: string): boolean {
  return table.members.some(
    (member) => member.key.toLowerCase() === key.toLowerCase(),
  );
}

function getTableContext(
  table: MapTable,
): "map" | "settings" | "includeList" | "includeConfig" {
  const parent = table.parentMember;
  if (!parent) return "map";
  if (parent.key.toLowerCase() === "_settings") return "settings";
  if (parent.key.toLowerCase() === "#include") return "includeList";
  if (
    parent.parent.parentMember?.key.toLowerCase() === "#include"
  ) {
    return "includeConfig";
  }
  return "map";
}

function isKeyPosition(
  parsed: ParsedMap,
  table: MapTable,
  offset: number,
): boolean {
  for (const member of table.members) {
    if (offset >= member.valueSpan.start && offset <= member.valueSpan.end) {
      return false;
    }
    if (offset >= member.keySpan.start && offset <= member.keySpan.end) {
      return true;
    }
  }

  const contentStart = Math.max(table.contentSpan.start, 0);
  const prefix = parsed.text.slice(contentStart, offset);
  const boundary = Math.max(prefix.lastIndexOf("\n"), prefix.lastIndexOf(";"));
  const current = prefix.slice(boundary + 1);
  return /^\s*(?:[\w-]*|'[^']*|\"[^\"]*)$/.test(current);
}

function getSettingValueSuggestions(
  parsed: ParsedMap,
  table: MapTable,
  offset: number,
): CompletionSuggestion[] | undefined {
  if (getTableContext(table) !== "settings") return undefined;

  const lineStart = Math.max(
    parsed.text.lastIndexOf("\n", offset - 1),
    parsed.text.lastIndexOf("\r", offset - 1),
  );
  const current = parsed.text.slice(lineStart + 1, offset);
  const assignment = current.match(
    /^\s*(Debug|Concurrently|TmuxAutoWindow|DiscoveryCache|DiscoveryCacheLocation|Process)\s*=\s*[$\w'"]*$/i,
  );
  return assignment
    ? settingValues[assignment[1].toLowerCase()]
    : undefined;
}

export function getCompletionSuggestions(
  parsed: ParsedMap,
  offset: number,
): CompletionSuggestion[] {
  const table = findTableAtOffset(parsed, offset);
  if (!table) return [];

  const valueSuggestions = getSettingValueSuggestions(parsed, table, offset);
  if (valueSuggestions) return valueSuggestions;
  if (isIgnoredOffset(parsed, offset) || !isKeyPosition(parsed, table, offset)) {
    return [];
  }

  let candidates: CompletionSuggestion[];
  switch (getTableContext(table)) {
    case "settings":
      candidates = settingSuggestions;
      break;
    case "includeConfig":
      candidates = includeSuggestions;
      break;
    case "includeList":
      return [];
    default:
      candidates = mapSuggestions;
      break;
  }

  return candidates.filter((suggestion) => !hasKey(table, suggestion.label));
}
