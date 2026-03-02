#!/usr/bin/env node
// Builds a standalone rubber-duck binary using esbuild (ESM→CJS) + @yao-pkg/pkg.
//
// Note on universal binaries: pkg embeds its JavaScript payload after the Mach-O
// binary. lipo(1) merges Mach-O segments but does not adjust the post-binary
// payload offsets, so lipo-combined pkg binaries are broken at runtime.
// We therefore build a single-arch binary for the current host (arm64 on Apple
// Silicon CI runners, x64 on Intel).  Rosetta 2 handles arm64→x64 transparently
// for any Intel Mac users.

import { execSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { build } from "esbuild";

const OUT_DIR = resolve("../cli-bin");
mkdirSync(OUT_DIR, { recursive: true });

const nativeArch = process.arch === "arm64" ? "arm64" : "x64";

// Step 1: esbuild bundles src/cli-binary.ts → CJS.
//
// cli-binary.ts uses an async IIFE (no top-level await) so esbuild can output
// CJS format (required by @yao-pkg/pkg).
//
// import.meta.url polyfill: banner injects pathToFileURL(__filename).href so that
// fileURLToPath(import.meta.url) works correctly at runtime (used by constants.ts
// to locate the local pi binary).
console.log("Step 1: bundling src/cli-binary.ts → dist/cli.cjs (esbuild CJS)");
await build({
  entryPoints: ["src/cli-binary.ts"],
  bundle: true,
  platform: "node",
  format: "cjs",
  outfile: "dist/cli.cjs",
  banner: {
    js: 'const { pathToFileURL: __pfu } = require("url"); const _importMetaUrl = __pfu(__filename).href;',
  },
  define: { "import.meta.url": "_importMetaUrl" },
  external: ["@mariozechner/pi-coding-agent"],
});
console.log("  → dist/cli.cjs");

// Step 2: pkg creates a native standalone binary.
console.log(`Step 2: pkg → cli-bin/rubber-duck (node22-macos-${nativeArch})`);
execSync(
  `npx pkg dist/cli.cjs --target node22-macos-${nativeArch} --output ${OUT_DIR}/rubber-duck`,
  { stdio: "inherit" }
);

execSync(`chmod +x ${OUT_DIR}/rubber-duck`, { stdio: "inherit" });
console.log(`Binary (${nativeArch}): ${OUT_DIR}/rubber-duck`);
