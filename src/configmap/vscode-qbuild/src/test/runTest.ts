import * as path from "node:path";
import { runTests } from "@vscode/test-electron";

async function main(): Promise<void> {
  const extensionDevelopmentPath = path.resolve(__dirname, "../..");
  const extensionTestsPath = path.resolve(__dirname, "suite", "index");
  const workspacePath = path.resolve(
    extensionDevelopmentPath,
    "src",
    "test",
    "fixtures",
    "workspace",
  );

  await runTests({
    extensionDevelopmentPath,
    extensionTestsPath,
    launchArgs: [workspacePath, "--disable-extensions"],
  });
}

main().catch((error: unknown) => {
  console.error("Extension-host tests failed:", error);
  process.exit(1);
});
