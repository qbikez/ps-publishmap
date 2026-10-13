const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const {
  PARTS,
  nextVersion,
  releaseTag,
  replaceVersionFields,
} = require("./version");

const extensionRoot = path.resolve(__dirname, "..");

function run(command, args, options = {}) {
  const capture = Boolean(options.encoding);
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? extensionRoot,
    stdio: capture ? ["inherit", "pipe", "pipe"] : "inherit",
    encoding: options.encoding,
    shell: options.shell ?? false,
  });
  if ((result.status ?? 1) !== 0) {
    const detail = capture && result.stderr ? result.stderr.trim() : "";
    throw new Error(
      `${command} ${args.join(" ")} failed.${detail ? `\n${detail}` : ""}`,
    );
  }
  return capture ? (result.stdout ?? "").trim() : undefined;
}

function parseArgs(argv) {
  let part = "patch";
  let notes;
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--notes") {
      notes = argv[index + 1];
      if (!notes) {
        throw new Error("--notes requires a value.");
      }
      index += 1;
      continue;
    }
    if (arg.startsWith("-")) {
      throw new Error(`Unknown argument '${arg}'.`);
    }
    part = arg;
  }
  if (!PARTS.includes(part)) {
    throw new Error(
      `Version part must be one of ${PARTS.join(", ")}. Got '${part}'.`,
    );
  }
  return { part, notes };
}

function readPackage() {
  return JSON.parse(
    fs.readFileSync(path.join(extensionRoot, "package.json"), "utf8"),
  );
}

function writeVersion(from, to) {
  const packagePath = path.join(extensionRoot, "package.json");
  const lockPath = path.join(extensionRoot, "package-lock.json");
  const packageText = fs.readFileSync(packagePath, "utf8");
  const lockText = fs.readFileSync(lockPath, "utf8");
  fs.writeFileSync(packagePath, replaceVersionFields(packageText, from, to, 1));
  fs.writeFileSync(lockPath, replaceVersionFields(lockText, from, to, 2));
  return () => {
    fs.writeFileSync(packagePath, packageText);
    fs.writeFileSync(lockPath, lockText);
  };
}

function main() {
  const { part, notes } = parseArgs(process.argv.slice(2));
  run("gh", ["auth", "status"]);

  const repoRoot = run("git", ["rev-parse", "--show-toplevel"], {
    encoding: "utf8",
  });
  const branch = run("git", ["rev-parse", "--abbrev-ref", "HEAD"], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  if (branch === "HEAD") {
    throw new Error("Release must run from a named branch.");
  }

  const extensionDir = path.relative(repoRoot, extensionRoot).replaceAll("\\", "/");
  const dirty = run(
    "git",
    ["status", "--porcelain", "--", extensionDir],
    { cwd: repoRoot, encoding: "utf8" },
  );
  if (dirty) {
    throw new Error(
      `Commit changes under ${extensionDir} before releasing.\n${dirty}`,
    );
  }

  const current = readPackage().version;
  const version = nextVersion(current, part);
  const tag = releaseTag(version);
  const existingTag = spawnSync(
    "git",
    ["rev-parse", "--verify", "--quiet", `refs/tags/${tag}`],
    { cwd: repoRoot },
  );
  if (existingTag.status === 0) {
    throw new Error(`Tag ${tag} already exists.`);
  }

  run("npm", ["run", "test:unit"], { shell: true });

  const restoreVersion = part === "current" ? () => {} : writeVersion(current, version);
  try {
    run("npm", ["run", "package"], { shell: true });
  } catch (error) {
    restoreVersion();
    throw error;
  }

  const vsix = path.join(extensionRoot, ".publish", `qbuild-map-tools-${version}.vsix`);
  if (!fs.existsSync(vsix)) {
    restoreVersion();
    throw new Error(`Packaged VSIX was not found at ${vsix}.`);
  }

  if (part !== "current") {
    run("git", ["add", "--", "package.json", "package-lock.json"], {
      cwd: extensionRoot,
    });
    run(
      "git",
      ["commit", "-m", `Release qbuild-map-tools ${version}`],
      { cwd: extensionRoot },
    );
  }

  run("git", ["tag", "-a", tag, "-m", `qbuild Map Tools ${version}`], {
    cwd: repoRoot,
  });
  run("git", ["push", "origin", branch], { cwd: repoRoot });
  run("git", ["push", "origin", tag], { cwd: repoRoot });
  run(
    "gh",
    [
      "release",
      "create",
      tag,
      vsix,
      "--verify-tag",
      "--target",
      branch,
      "--title",
      `qbuild Map Tools ${version}`,
      "--notes",
      notes || `qbuild Map Tools ${version}`,
    ],
    { cwd: repoRoot },
  );

  console.log(`Published ${tag}`);
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
