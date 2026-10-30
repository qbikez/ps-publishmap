const assert = require("node:assert/strict");
const test = require("node:test");
const {
  nextVersion,
  releaseTag,
  replaceVersionFields,
} = require("./version");

test("bumps numeric semver parts and can keep the current version", () => {
  assert.equal(nextVersion("0.1.0", "patch"), "0.1.1");
  assert.equal(nextVersion("0.1.9", "minor"), "0.2.0");
  assert.equal(nextVersion("1.4.2", "major"), "2.0.0");
  assert.equal(nextVersion("0.1.0", "current"), "0.1.0");
});

test("rejects unsupported versions and parts", () => {
  assert.throws(() => nextVersion("1.2.3-beta", "patch"), /major\.minor\.patch/);
  assert.throws(() => nextVersion("0.1.0", "build"), /Version part/);
});

test("uses a tag that is separate from the module version", () => {
  assert.equal(releaseTag("0.1.1"), "qbuild-map-tools-v0.1.1");
});

test("replaces only the requested number of version fields", () => {
  const text = `{
  "version": "0.1.0",
  "packages": { "": { "version": "0.1.0" } },
  "nested": { "version": "0.1.0" }
}`;

  assert.equal(
    replaceVersionFields(text, "0.1.0", "0.1.1", 2),
    `{
  "version": "0.1.1",
  "packages": { "": { "version": "0.1.1" } },
  "nested": { "version": "0.1.0" }
}`,
  );
});
