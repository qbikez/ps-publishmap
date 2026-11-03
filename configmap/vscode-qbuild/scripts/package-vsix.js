const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const pkg = require(path.join(root, "package.json"));
const publishDir = path.join(root, ".publish");
fs.mkdirSync(publishDir, { recursive: true });

const outFile = path.join(publishDir, `${pkg.name}-${pkg.version}.vsix`);
const vsce = path.join(
  root,
  "node_modules",
  ".bin",
  process.platform === "win32" ? "vsce.cmd" : "vsce",
);
const result = spawnSync(vsce, ["package", "--out", outFile], {
  cwd: root,
  stdio: "inherit",
  shell: process.platform === "win32",
});

process.exit(result.status ?? 1);
