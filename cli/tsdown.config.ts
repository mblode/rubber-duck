import { defineConfig } from "tsdown";

export default defineConfig([
  {
    entry: { cli: "src/cli.ts" },
    format: ["esm"],
    clean: true,
    sourcemap: true,
    target: "node22",
    banner: { js: "#!/usr/bin/env node" },
  },
  {
    entry: { index: "src/index.ts" },
    format: ["esm"],
    dts: true,
    sourcemap: true,
    target: "node22",
  },
  {
    entry: { daemon: "src/daemon/main.ts" },
    format: ["esm"],
    clean: false,
    sourcemap: true,
    target: "node22",
    banner: { js: "#!/usr/bin/env node" },
  },
]);
