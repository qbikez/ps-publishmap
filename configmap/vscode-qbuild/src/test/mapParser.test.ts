import assert from "node:assert/strict";
import test from "node:test";
import {
  findTableAtOffset,
  isIgnoredOffset,
  parseMap,
} from "../mapParser";

test("parses nested and ordered qbuild hashtables", () => {
  const text = `
$targets = [ordered]@{
  frontend = [ordered]@{
    build = {
      $data = @{ braces = "}" }
    }
    description = 'Frontend } commands'
  }
}
`;

  const parsed = parseMap(text);
  assert.equal(parsed.tables.length, 1);
  assert.deepEqual(
    parsed.tables[0].members.map((member) => member.key),
    ["frontend"],
  );

  const frontend = parsed.tables[0].members[0].table;
  assert.ok(frontend);
  assert.deepEqual(
    frontend.members.map((member) => member.key),
    ["build", "description"],
  );
  assert.equal(frontend.members[0].valueKind, "scriptblock");
});

test("ignores comments, strings, here-strings, and scriptblock map literals", () => {
  const text = `
@{
  # fake = @{ nope = {} }
  build = {
    $value = @'
@{ fake = { } }
'@
    $other = @{ nested = $true }
  }
  test = { "}" }
}
`;

  const parsed = parseMap(text);
  assert.deepEqual(
    parsed.tables[0].members.map((member) => member.key),
    ["build", "test"],
  );
  assert.equal(parsed.tables.length, 1);
  assert.equal(isIgnoredOffset(parsed, text.indexOf("fake =")), true);
});

test("returns the innermost table and tolerates unfinished input", () => {
  const text = "@{\n group = @{\n  child = {\n }\n ";
  const parsed = parseMap(text);
  const offset = text.indexOf("child");
  const table = findTableAtOffset(parsed, offset);

  assert.ok(table);
  assert.equal(table.parentMember?.key, "group");
  assert.deepEqual(
    table.members.map((member) => member.key),
    ["child"],
  );
  assert.equal(table.span.end, text.length);
});
