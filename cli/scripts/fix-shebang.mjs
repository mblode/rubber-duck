#!/usr/bin/env node

import { chmodSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const SHEBANG = "#!/usr/bin/env node";
const TARGETS = ["dist/cli.js", "dist/daemon.js"];

for (const target of TARGETS) {
  const filePath = resolve(target);
  if (!existsSync(filePath)) {
    continue;
  }

  const content = readFileSync(filePath, "utf8");
  if (content.startsWith(`${SHEBANG}\n`)) {
    chmodSync(filePath, 0o755);
    continue;
  }

  const withoutExistingShebang = content.startsWith("#!")
    ? content.slice(content.indexOf("\n") + 1)
    : content;
  writeFileSync(filePath, `${SHEBANG}\n${withoutExistingShebang}`, "utf8");
  chmodSync(filePath, 0o755);
}
