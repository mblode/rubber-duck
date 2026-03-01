import { defineConfig } from "tsdown";

const stripDefineFromRolldownInput = {
  "build:before": ({
    buildOptions,
  }: {
    buildOptions: Record<string, unknown>;
  }) => {
    // rolldown@1.0.0-rc.x rejects `define` as an input option.
    // tsdown injects it there by default, causing warning spam per entry.
    Reflect.deleteProperty(buildOptions, "define");
    // Same issue for `inject` in this toolchain combination.
    Reflect.deleteProperty(buildOptions, "inject");
  },
};

export default defineConfig([
  {
    entry: { cli: "src/cli.ts" },
    format: ["esm"],
    clean: true,
    sourcemap: true,
    target: "node22",
    banner: { js: "#!/usr/bin/env node" },
    hooks: stripDefineFromRolldownInput,
  },
  {
    entry: { index: "src/index.ts" },
    format: ["esm"],
    dts: true,
    sourcemap: true,
    target: "node22",
    hooks: stripDefineFromRolldownInput,
  },
  {
    entry: { daemon: "src/daemon/main.ts" },
    format: ["esm"],
    clean: false,
    sourcemap: true,
    target: "node22",
    banner: { js: "#!/usr/bin/env node" },
    hooks: stripDefineFromRolldownInput,
  },
]);
