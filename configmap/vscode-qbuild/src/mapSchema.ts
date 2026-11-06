import schemaJson from "./mapSchema.json";

export interface SchemaValue {
  value: string;
  detail: string;
}

export interface EntryKey {
  key: string;
  detail: string;
  insertText: string;
  retrigger?: boolean;
  /** Process types the key applies to; absent means every process. */
  processes?: string[];
}

export interface Setting {
  key: string;
  detail: string;
  type?: "boolean";
  default?: string;
  values?: SchemaValue[];
  valuesFrom?: "processes";
}

export interface TemplateKey {
  key: string;
  detail: string;
  insertText?: string;
  values?: SchemaValue[];
}

export interface TemplateType {
  type: string;
  shortForm: string;
  /** Key holding the file path in the hashtable form (`file` or `csproj`). */
  pathKey: string;
  /** Regular expression matched against file names the template can point at. */
  fileMatch: string;
  detail: string;
  keys: TemplateKey[];
}

export interface MapSchema {
  entryKeys: EntryKey[];
  settings: Setting[];
  processes: { name: string; detail: string }[];
  defaultProcess: string;
  processAliases: Record<string, string>;
  templates: TemplateType[];
}

export const mapSchema = schemaJson as MapSchema;

export function getCanonicalProcess(name: string): string {
  const lower = name.toLowerCase();
  const alias = Object.entries(mapSchema.processAliases).find(
    ([legacy]) => legacy.toLowerCase() === lower,
  );
  return alias ? alias[1] : lower;
}

export function findTemplateType(
  name: string,
  form: "type" | "shortForm",
): TemplateType | undefined {
  const lower = name.toLowerCase();
  return mapSchema.templates.find(
    (template) => template[form].toLowerCase() === lower,
  );
}
