import assert from "node:assert/strict";
import test from "node:test";
import { getCompletionSuggestions } from "../completionModel";
import { parseMap } from "../mapParser";
import { getQbuildSymbols } from "../symbolModel";

function marked(source: string): { text: string; offset: number } {
  const offset = source.indexOf("|");
  assert.notEqual(offset, -1);
  return {
    text: source.slice(0, offset) + source.slice(offset + 1),
    offset,
  };
}

function labels(source: string): string[] {
  const { text, offset } = marked(source);
  return getCompletionSuggestions(parseMap(text), offset).map(
    (suggestion) => suggestion.label,
  );
}

test("offers map metadata and suppresses keys already present", () => {
  const suggestions = labels(`
@{
  description = 'Build'
  |
}
`);

  assert.ok(suggestions.includes("_settings"));
  assert.ok(suggestions.includes("exec"));
  assert.ok(suggestions.includes("#include"));
  assert.ok(!suggestions.includes("description"));
});

test("offers settings and include configuration keys contextually", () => {
  const settings = labels(`
@{
  _settings = @{
    Debug = $true
    |
  }
}
`);
  assert.ok(settings.includes("DiscoveryCacheLocation"));
  assert.ok(settings.includes("Process"));
  assert.ok(!settings.includes("Debug"));
  assert.ok(!settings.includes("exec"));

  const includeConfig = labels(`
@{
  '#include' = @{
    child = @{
      |
    }
  }
}
`);
  assert.deepEqual(includeConfig, ["prefix"]);
});

test("offers known setting values", () => {
  assert.deepEqual(
    labels("@{ _settings = @{\n Debug = $|\n} }"),
    ["$true", "$false"],
  );
  assert.deepEqual(
    labels("@{ _settings = @{\n DiscoveryCacheLocation = '|\n} }"),
    ["local", "user"],
  );
  assert.deepEqual(
    labels("@{ _settings = @{\n Process = |\n} }"),
    ["qbuild", "qrun"],
  );
});

test("does not offer completions in values, scripts, strings, or comments", () => {
  assert.deepEqual(labels("@{ description = '|'; }"), []);
  assert.deepEqual(labels("@{ build = { | }; }"), []);
  assert.deepEqual(labels("@{\n # comment |\n}"), []);
});

test("builds hierarchical symbols and flattens list containers", () => {
  const text = `
[ordered]@{
  _settings = @{ Debug = $true }
  frontend = @{
    description = 'Frontend'
    list = @{
      build = @{ exec = { 'build' }; description = 'Build it' }
      test = { 'test' }
    }
  }
  clean = { 'clean' }
  '#include' = @{ child = @{ prefix = $true } }
}
`;

  const symbols = getQbuildSymbols(parseMap(text));
  assert.deepEqual(
    symbols.map((symbol) => symbol.name),
    ["frontend", "clean"],
  );
  assert.equal(symbols[0].kind, "group");
  assert.deepEqual(
    symbols[0].children.map((symbol) => [
      symbol.name,
      symbol.detail,
      symbol.kind,
    ]),
    [
      ["build", "frontend.build", "command"],
      ["test", "frontend.test", "command"],
    ],
  );
  assert.equal(symbols[1].detail, "clean");
  for (const symbol of [symbols[0], ...symbols[0].children, symbols[1]]) {
    assert.ok(symbol.span.start <= symbol.selectionSpan.start);
    assert.ok(symbol.span.end >= symbol.selectionSpan.end);
  }
});
