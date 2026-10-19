const PARTS = ["patch", "minor", "major", "current"];

function nextVersion(current, part) {
  if (!PARTS.includes(part)) {
    throw new Error(
      `Version part must be one of ${PARTS.join(", ")}. Got '${part}'.`,
    );
  }

  const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(current);
  if (!match) {
    throw new Error(
      `Version '${current}' must be numeric major.minor.patch.`,
    );
  }

  if (part === "current") {
    return current;
  }

  let major = Number(match[1]);
  let minor = Number(match[2]);
  let patch = Number(match[3]);
  if (part === "major") {
    major += 1;
    minor = 0;
    patch = 0;
  } else if (part === "minor") {
    minor += 1;
    patch = 0;
  } else {
    patch += 1;
  }

  return `${major}.${minor}.${patch}`;
}

function releaseTag(version) {
  return `qbuild-map-tools-v${version}`;
}

function replaceVersionFields(text, from, to, times) {
  const pattern = new RegExp(
    `("version"\\s*:\\s*")${from.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(")`,
    "g",
  );
  let seen = 0;
  const updated = text.replace(pattern, (match, prefix, suffix) => {
    seen += 1;
    return seen <= times ? `${prefix}${to}${suffix}` : match;
  });
  if (seen < times) {
    throw new Error(
      `Expected at least ${times} version field(s) matching ${from}, found ${seen}.`,
    );
  }
  return updated;
}

module.exports = {
  PARTS,
  nextVersion,
  releaseTag,
  replaceVersionFields,
};
