import {
  findTableAtOffset,
  isIgnoredOffset,
  MapMember,
  MapTable,
  ParsedMap,
} from "./mapParser";
import {
  findTemplateType,
  getCanonicalProcess,
  mapSchema,
  Setting,
  TemplateType,
} from "./mapSchema";

export interface CompletionSuggestion {
  label: string;
  detail: string;
  insertText: string;
  isSnippet?: boolean;
  /** Offset the inserted text replaces from; the provider picks a word range when absent. */
  replaceStart?: number;
  /** Open completion again after inserting, for values completed in two parts. */
  retrigger?: boolean;
}

export interface CompletionEnvironment {
  /** Files near the map, relative to its directory, with `/` separators. */
  listFiles?: () => string[];
}

type TableContext =
  | "map"
  | "settings"
  | "includeList"
  | "includeConfig"
  | "template";

interface Assignment {
  key: string;
  value: string;
  valueStart: number;
}

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

function findMember(table: MapTable, key: string): MapMember | undefined {
  const lower = key.toLowerCase();
  return table.members.find((member) => member.key.toLowerCase() === lower);
}

function hasKey(table: MapTable, key: string): boolean {
  return findMember(table, key) !== undefined;
}

function getMemberValueText(parsed: ParsedMap, member: MapMember): string {
  return parsed.text
    .slice(member.valueSpan.start, member.valueSpan.end)
    .trim()
    .replace(/^(['"])(.*)\1$/s, "$2");
}

function getTableContext(table: MapTable): TableContext {
  const parent = table.parentMember;
  if (!parent) return "map";
  const key = parent.key.toLowerCase();
  if (key === "_settings") return "settings";
  if (key === "#include") return "includeList";
  if (key === "_template") return "template";
  if (parent.parent.parentMember?.key.toLowerCase() === "#include") {
    return "includeConfig";
  }
  return "map";
}

/** The process of the entry at `table`: its own `_settings.process` or the nearest ancestor's. */
function getEntryProcess(parsed: ParsedMap, table: MapTable): string {
  for (
    let current: MapTable | undefined = table;
    current;
    current = current.parentMember?.parent
  ) {
    const settings = findMember(current, "_settings")?.table;
    const process = settings && findMember(settings, "process");
    if (process) {
      return getCanonicalProcess(getMemberValueText(parsed, process));
    }
  }
  return mapSchema.defaultProcess;
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

/** The `key = value` assignment the cursor is typing the value of, if any. */
function getAssignmentAt(
  parsed: ParsedMap,
  table: MapTable,
  offset: number,
): Assignment | undefined {
  const text = parsed.text;
  const start = Math.max(
    table.contentSpan.start,
    text.lastIndexOf("\n", offset - 1) + 1,
    text.lastIndexOf("\r", offset - 1) + 1,
    text.lastIndexOf(";", offset - 1) + 1,
  );
  const match = text
    .slice(start, offset)
    .match(/^\s*['"]?([\w#-]+)['"]?\s*=\s*(.*)$/);
  if (!match) return undefined;
  return {
    key: match[1].toLowerCase(),
    value: match[2],
    valueStart: offset - match[2].length,
  };
}

function isQuoted(value: string): boolean {
  return /^['"]/.test(value);
}

/** Suggestions for a string value: bare text inside an open quote, quoted text otherwise. */
function stringValueSuggestion(
  assignment: Assignment,
  label: string,
  detail: string,
  retrigger = false,
): CompletionSuggestion {
  const quoted = isQuoted(assignment.value);
  return {
    label,
    detail,
    insertText: quoted ? label : `'${label}'`,
    replaceStart: assignment.valueStart + (quoted ? 1 : 0),
    retrigger,
  };
}

function getSettingValues(setting: Setting): CompletionSuggestion[] {
  if (setting.type === "boolean") return booleanValueSuggestions;
  const values =
    setting.valuesFrom === "processes"
      ? mapSchema.processes.map(({ name, detail }) => ({ value: name, detail }))
      : (setting.values ?? []);
  return values.map(({ value, detail }) => ({
    label: value,
    detail,
    insertText: `'${value}'`,
  }));
}

function getSettingKeyInsertText(setting: Setting): string {
  if (setting.type === "boolean") {
    return `${setting.key} = ${setting.default ?? "$false"}`;
  }
  const values = getSettingValues(setting).map((value) => value.label);
  return `${setting.key} = '\${1|${values.join(",")}|}'`;
}

function getFileSuggestions(
  template: TemplateType,
  replaceStart: number,
  quote: boolean,
  environment: CompletionEnvironment,
): CompletionSuggestion[] {
  const pattern = new RegExp(template.fileMatch, "i");
  return (environment.listFiles?.() ?? [])
    .filter((file) => pattern.test(file.slice(file.lastIndexOf("/") + 1)))
    .map((file) => ({
      label: file,
      detail: template.detail,
      insertText: quote ? `'${file}'` : file,
      replaceStart,
    }));
}

/** `_template = '<shortForm>:<path>'`: short forms first, then files for the chosen form. */
function getTemplateShortFormValues(
  assignment: Assignment,
  environment: CompletionEnvironment,
): CompletionSuggestion[] {
  const quoted = isQuoted(assignment.value);
  const body = quoted ? assignment.value.slice(1) : assignment.value;
  const bodyStart = assignment.valueStart + (quoted ? 1 : 0);
  const colon = body.indexOf(":");

  if (colon < 0) {
    return mapSchema.templates.map((template) => ({
      label: `${template.shortForm}:`,
      detail: template.detail,
      insertText: quoted
        ? `${template.shortForm}:`
        : `'${template.shortForm}:\${1}'`,
      isSnippet: !quoted,
      replaceStart: bodyStart,
      retrigger: true,
    }));
  }

  const template = findTemplateType(body.slice(0, colon), "shortForm");
  if (!template) return [];
  return getFileSuggestions(template, bodyStart + colon + 1, false, environment);
}

function getDeclaredTemplateType(
  parsed: ParsedMap,
  table: MapTable,
): TemplateType | undefined {
  const type = findMember(table, "type");
  return type && findTemplateType(getMemberValueText(parsed, type), "type");
}

function getTemplateTableValues(
  parsed: ParsedMap,
  table: MapTable,
  assignment: Assignment,
  environment: CompletionEnvironment,
): CompletionSuggestion[] | undefined {
  if (assignment.key === "type") {
    return mapSchema.templates.map((template) =>
      stringValueSuggestion(assignment, template.type, template.detail),
    );
  }

  const template = getDeclaredTemplateType(parsed, table);
  if (!template) return undefined;
  if (assignment.key === template.pathKey.toLowerCase()) {
    const quoted = isQuoted(assignment.value);
    return getFileSuggestions(
      template,
      assignment.valueStart + (quoted ? 1 : 0),
      !quoted,
      environment,
    );
  }

  const key = template.keys.find(
    (candidate) => candidate.key.toLowerCase() === assignment.key,
  );
  return key?.values?.map(({ value, detail }) => ({
    label: value,
    detail,
    insertText: value,
  }));
}

function getValueSuggestions(
  parsed: ParsedMap,
  table: MapTable,
  offset: number,
  environment: CompletionEnvironment,
): CompletionSuggestion[] | undefined {
  const assignment = getAssignmentAt(parsed, table, offset);
  if (!assignment) return undefined;

  switch (getTableContext(table)) {
    case "settings": {
      const setting = mapSchema.settings.find(
        (candidate) => candidate.key.toLowerCase() === assignment.key,
      );
      return setting && getSettingValues(setting);
    }
    case "template":
      return getTemplateTableValues(parsed, table, assignment, environment);
    case "map":
      return assignment.key === "_template"
        ? getTemplateShortFormValues(assignment, environment)
        : undefined;
    default:
      return undefined;
  }
}

function getTemplateTableKeys(
  parsed: ParsedMap,
  table: MapTable,
): CompletionSuggestion[] {
  const template = getDeclaredTemplateType(parsed, table);
  if (!template) {
    return [
      {
        label: "type",
        detail: "Template type: appconfig, dotenv or user-secrets",
        insertText: "type = '${1}'",
        isSnippet: true,
        retrigger: true,
      },
    ];
  }

  return [
    {
      label: template.pathKey,
      detail: `Path of the ${template.type} file, relative to the map`,
      insertText: `${template.pathKey} = '\${1}'`,
      isSnippet: true,
      retrigger: true,
    },
    ...template.keys.map((key) => ({
      label: key.key,
      detail: key.detail,
      insertText:
        key.insertText ?? `${key.key} = ${key.values?.[0]?.value ?? "''"}`,
      isSnippet: key.insertText !== undefined,
    })),
  ];
}

function getKeySuggestions(
  parsed: ParsedMap,
  table: MapTable,
): CompletionSuggestion[] {
  switch (getTableContext(table)) {
    case "settings":
      return mapSchema.settings.map((setting) => ({
        label: setting.key,
        detail: setting.detail,
        insertText: getSettingKeyInsertText(setting),
        isSnippet: setting.type !== "boolean",
      }));
    case "includeConfig":
      return includeSuggestions;
    case "includeList":
      return [];
    case "template":
      return getTemplateTableKeys(parsed, table);
    case "map": {
      const process = getEntryProcess(parsed, table);
      return mapSchema.entryKeys
        .filter((key) => !key.processes || key.processes.includes(process))
        .map((key) => ({
          label: key.key,
          detail: key.detail,
          insertText: key.insertText,
          isSnippet: true,
          retrigger: key.retrigger,
        }));
    }
  }
}

export function getCompletionSuggestions(
  parsed: ParsedMap,
  offset: number,
  environment: CompletionEnvironment = {},
): CompletionSuggestion[] {
  const table = findTableAtOffset(parsed, offset);
  if (!table) return [];

  const valueSuggestions = getValueSuggestions(
    parsed,
    table,
    offset,
    environment,
  );
  if (valueSuggestions) return valueSuggestions;
  if (isIgnoredOffset(parsed, offset) || !isKeyPosition(parsed, table, offset)) {
    return [];
  }

  return getKeySuggestions(parsed, table).filter(
    (suggestion) => !hasKey(table, suggestion.label),
  );
}
