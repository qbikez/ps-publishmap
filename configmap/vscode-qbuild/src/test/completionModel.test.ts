import assert from "node:assert/strict";
import test from "node:test";
import {
  CompletionSuggestion,
  getCompletionSuggestions,
} from "../completionModel";
import { parseMap } from "../mapParser";

const files = [
  ".env",
  ".env.example",
  "appsettings.json",
  "appsettings.Development.json",
  "package.json",
  "src/Api/Api.csproj",
];

function suggest(source: string): {
  suggestions: CompletionSuggestion[];
  offset: number;
} {
  const offset = source.indexOf("|");
  assert.notEqual(offset, -1);
  const text = source.slice(0, offset) + source.slice(offset + 1);
  return {
    suggestions: getCompletionSuggestions(parseMap(text), offset, {
      listFiles: () => files,
    }),
    offset,
  };
}

function labels(source: string): string[] {
  return suggest(source).suggestions.map((suggestion) => suggestion.label);
}

test("offers every ConfigMap setting", () => {
  const settings = labels("@{ _settings = @{\n |\n} }");
  assert.ok(settings.includes("ForceCheck"));
  assert.ok(settings.includes("UseWorkDir"));
});

test("offers exec only for entries whose process runs it", () => {
  const plain = labels("@{\n build = @{\n  |\n }\n}");
  assert.ok(plain.includes("exec"));
  assert.ok(!plain.includes("_template"));

  const steps = labels(
    "@{\n setup = @{\n  _settings = @{ process = 'steps' }\n  |\n }\n}",
  );
  assert.ok(steps.includes("exec"));

  const bun = labels(
    "@{\n web = @{\n  _settings = @{ process = 'bun' }\n  |\n }\n}",
  );
  assert.ok(!bun.includes("exec"));
  assert.ok(bun.includes("description"));
});

test("offers configuration keys in options entries", () => {
  const options = labels(
    "@{\n api = @{\n  _settings = @{ process = 'options' }\n  |\n }\n}",
  );
  for (const key of ["_template", "options", "get", "set", "validate"]) {
    assert.ok(options.includes(key), `missing ${key}`);
  }
  assert.ok(!options.includes("exec"));
});

test("resolves the process from legacy names and parent entries", () => {
  const legacy = labels(
    "@{\n api = @{\n  _settings = @{ process = \"qconf\" }\n  |\n }\n}",
  );
  assert.ok(legacy.includes("_template"));

  const inherited = labels(`
@{
  config = @{
    _settings = @{ process = 'options' }
    api = @{
      |
    }
  }
}`);
  assert.ok(inherited.includes("_template"));
  assert.ok(!inherited.includes("exec"));
});

test("offers _template short forms", () => {
  assert.deepEqual(
    labels("@{ api = @{\n _settings = @{ process = 'options' }\n _template = '|'\n} }"),
    ["appsettings:", "dotenv:", "user-secrets:"],
  );
});

test("offers matching files after a _template short form", () => {
  const { suggestions, offset } = suggest(
    "@{ api = @{\n _template = 'dotenv:.e|'\n} }",
  );
  assert.deepEqual(
    suggestions.map((suggestion) => suggestion.label),
    [".env", ".env.example"],
  );
  assert.equal(suggestions[0].replaceStart, offset - ".e".length);

  assert.deepEqual(
    labels("@{ api = @{\n _template = 'appsettings:|'\n} }"),
    ["appsettings.json", "appsettings.Development.json"],
  );
  assert.deepEqual(
    labels("@{ api = @{\n _template = 'user-secrets:|'\n} }"),
    ["src/Api/Api.csproj"],
  );
});

test("offers _template table keys for the declared type", () => {
  assert.deepEqual(labels("@{ api = @{\n _template = @{\n  |\n }\n} }"), [
    "type",
  ]);
  assert.deepEqual(
    labels("@{ api = @{\n _template = @{\n  type = 'dotenv'\n  |\n }\n} }"),
    ["file", "keys", "exclude"],
  );
  assert.deepEqual(
    labels("@{ api = @{\n _template = @{ type = 'user-secrets'; | }\n} }"),
    ["csproj"],
  );
});

test("offers _template table values", () => {
  assert.deepEqual(labels("@{ api = @{\n _template = @{ type = '|' }\n} }"), [
    "appconfig",
    "dotenv",
    "user-secrets",
  ]);
  assert.deepEqual(
    labels("@{ api = @{\n _template = @{ type = 'dotenv'; keys = | }\n} }"),
    ["'auto'"],
  );
  assert.deepEqual(
    labels("@{ api = @{\n _template = @{ type = 'dotenv'; file = '|' }\n} }"),
    [".env", ".env.example"],
  );
});
