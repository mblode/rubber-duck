/**
 * voice-tools.ts
 *
 * TypeScript implementation of voice tools previously executed in Swift.
 * Matches the behavior of Rubber Duck/Tools/ToolExecutor.swift exactly:
 * path containment validation, output limits, safe mode, error message format.
 */

import { spawn } from "node:child_process";
import {
  type Dirent,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  type Stats,
  statSync,
  writeFileSync,
} from "node:fs";
import { realpath } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { minimatch } from "minimatch";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_OUTPUT_BYTES = 102_400; // 100 KB
const MAX_FILE_BYTES = 1_048_576; // 1 MB
const MAX_FIND_RESULTS = 200;
const MAX_FIND_WARNINGS = 5;
const BASH_TIMEOUT_MS = 30_000; // 30 seconds
const WEB_SEARCH_TIMEOUT_MS = 15_000; // 15 seconds
const WEB_SEARCH_MAX_RESULTS = 10;
const WEB_SEARCH_DEFAULT_RESULTS = 5;
const EXA_SEARCH_ENDPOINT = "https://api.exa.ai/search";

const SKIP_DIRS = new Set([".git", ".build", "node_modules"]);

const SAFE_MODE_ALLOWED_PREFIXES = [
  ["git"],
  ["grep"],
  ["rg"],
  ["find"],
  ["ls"],
  ["cat"],
  ["head"],
  ["tail"],
  ["wc"],
  ["swift", "test"],
  ["xcodebuild", "test"],
  ["npm", "test"],
  ["pytest"],
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function extractStringArg(
  args: Record<string, unknown>,
  keys: string[]
): string | null {
  for (const key of keys) {
    const value = args[key];
    if (typeof value === "string" && value.trim().length > 0) {
      return value;
    }
  }
  return null;
}

function extractStringArrayArg(
  args: Record<string, unknown>,
  keys: string[]
): string[] | null {
  for (const key of keys) {
    const value = args[key];
    if (!Array.isArray(value)) {
      continue;
    }
    const cleaned = value
      .filter((entry): entry is string => typeof entry === "string")
      .map((entry) => entry.trim())
      .filter((entry) => entry.length > 0);
    if (cleaned.length > 0) {
      return cleaned;
    }
  }
  return null;
}

function normalizeArgs(
  toolName: string,
  parsedArgs: unknown
): Record<string, unknown> | null {
  if (isRecord(parsedArgs)) {
    return parsedArgs;
  }

  // Be lenient for common single-string call formats emitted by voice models.
  if (typeof parsedArgs === "string") {
    switch (toolName) {
      case "read_file":
        return { path: parsedArgs };
      case "bash":
        return { command: parsedArgs };
      case "grep_search":
      case "find_files":
        return { pattern: parsedArgs };
      case "web_search":
        return { query: parsedArgs };
      default:
        return null;
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// Path utilities
// ---------------------------------------------------------------------------

/**
 * Resolve a potentially relative path within the workspace.
 * Returns the absolute path, or null if the path escapes the workspace.
 */
async function resolvePath(
  path: string,
  workspaceRoot: string
): Promise<string | null> {
  const candidate = path.startsWith("/") ? path : join(workspaceRoot, path);

  // Walk up to find the deepest existing ancestor, then reconstruct
  const canonicalized = await canonicalizeForContainment(candidate);
  const candidateReal = canonicalized ?? resolve(candidate);

  if (!isWithinDirectory(candidateReal, workspaceRoot)) {
    return null;
  }
  return candidateReal;
}

async function resolveWorkspaceRoot(
  workspacePath: string
): Promise<string | null> {
  const workspaceRoot = await realpathSafe(workspacePath);
  if (!workspaceRoot) {
    return null;
  }
  try {
    if (!statSync(workspaceRoot).isDirectory()) {
      return null;
    }
    return workspaceRoot;
  } catch {
    return null;
  }
}

async function realpathSafe(p: string): Promise<string | null> {
  try {
    return await realpath(p);
  } catch {
    return existsSync(p) ? resolve(p) : null;
  }
}

async function canonicalizeForContainment(p: string): Promise<string | null> {
  const abs = resolve(p);

  // Fast path: path already exists — just canonicalize symlinks.
  if (existsSync(abs)) {
    try {
      return await realpath(abs);
    } catch {
      return abs;
    }
  }

  // Slow path: walk up to find deepest existing ancestor, then re-attach trailing segments.
  let current = abs;
  const trailing: string[] = [];
  while (!existsSync(current)) {
    const parent = resolve(current, "..");
    if (parent === current) {
      return abs; // hit filesystem root
    }
    trailing.unshift(current.split("/").at(-1) ?? "");
    current = parent;
  }
  try {
    const real = await realpath(current);
    return trailing.length > 0 ? join(real, ...trailing) : real;
  } catch {
    return trailing.length > 0 ? join(current, ...trailing) : current;
  }
}

function isWithinDirectory(candidate: string, root: string): boolean {
  if (candidate === root) {
    return true;
  }
  const rootWithSlash = root.endsWith("/") ? root : `${root}/`;
  return candidate.startsWith(rootWithSlash);
}

function toPosixPath(path: string): string {
  return path.replaceAll("\\", "/");
}

function toWorkspaceRelativePath(
  fullPath: string,
  workspaceRoot: string
): string {
  return toPosixPath(relative(workspaceRoot, fullPath));
}

// ---------------------------------------------------------------------------
// Output helpers
// ---------------------------------------------------------------------------

function truncateOutput(s: string): string {
  const bytes = Buffer.byteLength(s, "utf8");
  if (bytes <= MAX_OUTPUT_BYTES) {
    return s;
  }
  return (
    Buffer.from(s).subarray(0, MAX_OUTPUT_BYTES).toString("utf8") +
    "\n[Output truncated at 100KB]"
  );
}

// ---------------------------------------------------------------------------
// Tool: read_file
// ---------------------------------------------------------------------------

async function readFile(
  args: Record<string, unknown>,
  workspaceRoot: string
): Promise<string> {
  const path = extractStringArg(args, [
    "path",
    "file",
    "filepath",
    "file_path",
    "filename",
  ]);
  if (!path) {
    return "Error: Missing required parameter 'path'";
  }

  const resolved = await resolvePath(path, workspaceRoot);
  if (!resolved) {
    return "Error: Path escapes workspace root";
  }

  if (!existsSync(resolved)) {
    return `Error: File not found at '${path}'`;
  }

  try {
    const s = statSync(resolved);
    if (s.size > MAX_FILE_BYTES) {
      return `Error: File exceeds 1MB limit (${s.size} bytes)`;
    }
    return readFileSync(resolved, "utf8");
  } catch (err) {
    return `Error: Failed to read file: ${String(err)}`;
  }
}

// ---------------------------------------------------------------------------
// Tool: write_file
// ---------------------------------------------------------------------------

async function writeFile(
  args: Record<string, unknown>,
  workspaceRoot: string,
  safeMode: boolean
): Promise<string> {
  if (safeMode) {
    return "Error: write_file is disabled in safe mode";
  }

  const path = extractStringArg(args, [
    "path",
    "file",
    "filepath",
    "file_path",
    "filename",
  ]);
  if (!path) {
    return "Error: Missing required parameter 'path'";
  }

  const content = args.content;
  if (typeof content !== "string") {
    return "Error: Missing required parameter 'content'";
  }

  const resolved = await resolvePath(path, workspaceRoot);
  if (!resolved) {
    return "Error: Path escapes workspace root";
  }

  try {
    mkdirSync(dirname(resolved), { recursive: true });
    const data = Buffer.from(content, "utf8");
    writeFileSync(resolved, data);
    return `Successfully wrote ${data.byteLength} bytes to ${path}`;
  } catch (err) {
    return `Error: Failed to write file: ${String(err)}`;
  }
}

// ---------------------------------------------------------------------------
// Tool: edit_file
// ---------------------------------------------------------------------------

async function editFile(
  args: Record<string, unknown>,
  workspaceRoot: string,
  safeMode: boolean
): Promise<string> {
  if (safeMode) {
    return "Error: edit_file is disabled in safe mode";
  }

  const path = extractStringArg(args, [
    "path",
    "file",
    "filepath",
    "file_path",
    "filename",
  ]);
  if (!path) {
    return "Error: Missing required parameter 'path'";
  }

  const oldText = extractStringArg(args, ["old_text", "oldText", "find"]);
  if (!oldText) {
    return "Error: Missing required parameter 'old_text'";
  }

  const newText = extractStringArg(args, ["new_text", "newText", "replace"]);
  if (!newText) {
    return "Error: Missing required parameter 'new_text'";
  }

  const resolved = await resolvePath(path, workspaceRoot);
  if (!resolved) {
    return "Error: Path escapes workspace root";
  }

  try {
    const content = readFileSync(resolved, "utf8");
    const occurrences = content.split(oldText).length - 1;
    if (occurrences === 0) {
      return "Error: old_text not found in file";
    }
    if (occurrences > 1) {
      return `Error: old_text found ${occurrences} times (ambiguous edit)`;
    }

    const updated = content.replace(oldText, newText);
    writeFileSync(resolved, updated, "utf8");
    return `Successfully edited ${path}`;
  } catch (err) {
    return `Error: Failed to edit file: ${String(err)}`;
  }
}

// ---------------------------------------------------------------------------
// Tool: bash
// ---------------------------------------------------------------------------

function bash(
  args: Record<string, unknown>,
  workspaceRoot: string,
  safeMode: boolean
): Promise<string> {
  const command = extractStringArg(args, ["command", "cmd"]);
  if (!command) {
    return Promise.resolve("Error: Missing required parameter 'command'");
  }

  return new Promise((resolve) => {
    let proc: ReturnType<typeof spawn>;

    if (safeMode) {
      let parsed: string[];
      try {
        parsed = parseCommandArgs(command);
      } catch {
        return resolve("Error: Invalid command syntax in safe mode");
      }
      const allowed = SAFE_MODE_ALLOWED_PREFIXES.some(
        (prefix) =>
          parsed.slice(0, prefix.length).join(" ") === prefix.join(" ")
      );
      if (!allowed) {
        return resolve("Error: Command not allowed in safe mode");
      }
      proc = spawn(parsed[0], parsed.slice(1), { cwd: workspaceRoot });
    } else if (existsSync("/bin/zsh")) {
      proc = spawn("/bin/zsh", ["-c", command], { cwd: workspaceRoot });
    } else if (existsSync("/bin/bash")) {
      proc = spawn("/bin/bash", ["-lc", command], { cwd: workspaceRoot });
    } else {
      proc = spawn("sh", ["-c", command], { cwd: workspaceRoot });
    }

    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];

    proc.stdout?.on("data", (chunk: Buffer) => stdoutChunks.push(chunk));
    proc.stderr?.on("data", (chunk: Buffer) => stderrChunks.push(chunk));

    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      proc.kill("SIGTERM");
    }, BASH_TIMEOUT_MS);

    proc.on("close", (code) => {
      clearTimeout(timer);
      const stdout = Buffer.concat(stdoutChunks).toString("utf8");
      const stderr = Buffer.concat(stderrChunks).toString("utf8");

      let output = "";
      if (stdout) {
        output += stdout;
      }
      if (stderr) {
        output += (output ? "\n" : "") + stderr;
      }

      output = truncateOutput(output);
      if (timedOut) {
        output += "\n[Process timed out after 30s and was terminated]";
      }
      output += `\n[Exit code: ${code ?? "unknown"}]`;

      resolve(output);
    });

    proc.on("error", (err) => {
      clearTimeout(timer);
      resolve(`Error: Failed to launch process: ${err.message}`);
    });
  });
}

// biome-ignore lint/complexity/noExcessiveCognitiveComplexity: simple shell tokenizer
function parseCommandArgs(command: string): string[] {
  const trimmed = command.trim();
  if (!trimmed) {
    throw new Error("Empty command");
  }

  const args: string[] = [];
  let current = "";
  let inQuote: string | null = null;
  let escaping = false;

  for (const ch of trimmed) {
    if (escaping) {
      current += ch;
      escaping = false;
      continue;
    }
    if (ch === "\\") {
      if (inQuote === "'") {
        current += ch;
      } else {
        escaping = true;
      }
      continue;
    }
    if (inQuote) {
      if (ch === inQuote) {
        inQuote = null;
      } else {
        current += ch;
      }
      continue;
    }
    if (ch === "'" || ch === '"') {
      inQuote = ch;
      continue;
    }
    if (ch === " " || ch === "\t") {
      if (current) {
        args.push(current);
        current = "";
      }
      continue;
    }
    current += ch;
  }

  if (inQuote) {
    throw new Error("Unterminated quote");
  }
  if (current) {
    args.push(current);
  }
  if (!args.length) {
    throw new Error("Empty command");
  }
  return args;
}

// ---------------------------------------------------------------------------
// Tool: grep_search
// ---------------------------------------------------------------------------

async function grepSearch(
  args: Record<string, unknown>,
  workspaceRoot: string
): Promise<string> {
  const pattern = extractStringArg(args, ["pattern", "query", "regex"]);
  if (!pattern) {
    return "Error: Missing required parameter 'pattern'";
  }

  let searchPath = workspaceRoot;
  const requestedPath = extractStringArg(args, ["path", "directory", "dir"]);
  if (requestedPath) {
    const resolved = await resolvePath(requestedPath, workspaceRoot);
    if (!resolved) {
      return "Error: Path escapes workspace root";
    }
    searchPath = resolved;
  }

  const grepArgs = ["-rn", pattern, searchPath];
  if (typeof args.include === "string") {
    grepArgs.unshift(`--include=${args.include}`);
  }

  return new Promise((resolveP) => {
    const proc = spawn("grep", grepArgs, { cwd: workspaceRoot });
    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];

    proc.stdout?.on("data", (chunk: Buffer) => stdoutChunks.push(chunk));
    proc.stderr?.on("data", (chunk: Buffer) => stderrChunks.push(chunk));

    proc.on("close", (code) => {
      if (code === 1) {
        return resolveP("No matches found");
      }

      const stderr = Buffer.concat(stderrChunks).toString("utf8").trim();
      if (code !== 0) {
        return resolveP(
          stderr
            ? `Error: grep failed with exit code ${code}: ${stderr}`
            : `Error: grep failed with exit code ${code}`
        );
      }

      const output = Buffer.concat(stdoutChunks).toString("utf8");
      if (!output) {
        return resolveP("No matches found");
      }
      resolveP(truncateOutput(output));
    });

    proc.on("error", (err) =>
      resolveP(`Error: Failed to launch grep: ${err.message}`)
    );
  });
}

// ---------------------------------------------------------------------------
// Tool: find_files
// ---------------------------------------------------------------------------

function matchesGlobPattern(
  pattern: string,
  baseName: string,
  workspaceRelativePath: string,
  searchRelativePath: string,
  includeHidden: boolean
): boolean {
  const normalizedPattern = toPosixPath(pattern.trim());
  if (!normalizedPattern) {
    return false;
  }

  const options = {
    dot: includeHidden,
    nocase: true,
    matchBase: true,
  };

  const candidates = [
    baseName,
    workspaceRelativePath,
    searchRelativePath,
    `/${workspaceRelativePath}`,
    `/${searchRelativePath}`,
  ];

  return candidates.some((candidate) =>
    minimatch(candidate, normalizedPattern, options)
  );
}

async function findFiles(
  args: Record<string, unknown>,
  workspaceRoot: string
): Promise<string> {
  const pattern = extractStringArg(args, ["pattern", "glob"]) ?? "**/*";
  const includeHidden = args.include_hidden === true;
  const includeDirectories = args.include_directories === true;

  let searchRoot = workspaceRoot;
  const requestedPath = extractStringArg(args, ["path", "directory", "dir"]);
  if (requestedPath) {
    const resolved = await resolvePath(requestedPath, workspaceRoot);
    if (!resolved) {
      return "Error: Path escapes workspace root";
    }
    searchRoot = resolved;
  }

  if (!existsSync(searchRoot)) {
    return `Error: Search path not found: '${requestedPath ?? "."}'`;
  }

  let searchRootStats: Stats;
  try {
    searchRootStats = statSync(searchRoot);
  } catch (err) {
    return `Error: Failed to access search path: ${String(err)}`;
  }

  if (!searchRootStats.isDirectory()) {
    return `Error: Search path is not a directory: '${requestedPath ?? "."}'`;
  }

  const results: string[] = [];
  const warnings = new Set<string>();

  // biome-ignore lint/complexity/noExcessiveCognitiveComplexity: recursive directory walker
  function walk(dir: string): void {
    if (results.length >= MAX_FIND_RESULTS) {
      return;
    }

    let entries: Dirent[];
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch (err) {
      if (warnings.size < MAX_FIND_WARNINGS) {
        warnings.add(
          `${toWorkspaceRelativePath(dir, workspaceRoot)} (${String(err)})`
        );
      }
      return;
    }

    for (const entry of entries) {
      if (results.length >= MAX_FIND_RESULTS) {
        break;
      }
      const entryName = entry.name;

      if (!includeHidden && entryName.startsWith(".")) {
        continue;
      }

      if (SKIP_DIRS.has(entryName)) {
        continue;
      }

      const fullPath = join(dir, entryName);
      const workspaceRelativePath = toWorkspaceRelativePath(
        fullPath,
        workspaceRoot
      );
      const searchRelativePath = toPosixPath(relative(searchRoot, fullPath));

      let isDirectory = entry.isDirectory();
      let isFile = entry.isFile();
      if (!(isDirectory || isFile)) {
        try {
          const stats = statSync(fullPath);
          isDirectory = stats.isDirectory();
          isFile = stats.isFile();
        } catch (err) {
          if (warnings.size < MAX_FIND_WARNINGS) {
            warnings.add(`${workspaceRelativePath} (${String(err)})`);
          }
          continue;
        }
      }

      const matches = matchesGlobPattern(
        pattern,
        entryName,
        workspaceRelativePath,
        searchRelativePath,
        includeHidden
      );

      if (matches && (isFile || (includeDirectories && isDirectory))) {
        results.push(workspaceRelativePath);
      }

      if (isDirectory) {
        walk(fullPath);
      }
    }
  }

  walk(searchRoot);

  const sortedResults = [...results].sort((a, b) => a.localeCompare(b));
  const outputLines = sortedResults;

  if (outputLines.length >= MAX_FIND_RESULTS) {
    outputLines.push(`[Results truncated at ${MAX_FIND_RESULTS} entries]`);
  }

  if (warnings.size > 0) {
    outputLines.push(`[Warning: Skipped ${warnings.size} unreadable path(s)]`);
    for (const warning of warnings) {
      outputLines.push(`[Warning] ${warning}`);
    }
  }

  if (outputLines.length === 0) {
    if (pattern.trim() === "**/*") {
      return "Workspace scan complete: no non-hidden files found. Try include_hidden=true to list dotfiles.";
    }
    return `No files found matching '${pattern}'`;
  }

  return outputLines.join("\n");
}

// ---------------------------------------------------------------------------
// Tool: web_search
// ---------------------------------------------------------------------------

function parseBoundedPositiveInt(
  value: unknown,
  min: number,
  max: number
): number | null {
  let parsed: number | null = null;
  if (typeof value === "number" && Number.isFinite(value)) {
    parsed = Math.trunc(value);
  } else if (typeof value === "string" && value.trim().length > 0) {
    const maybe = Number.parseInt(value.trim(), 10);
    if (Number.isFinite(maybe)) {
      parsed = maybe;
    }
  }

  if (parsed === null) {
    return null;
  }
  if (parsed < min) {
    return min;
  }
  if (parsed > max) {
    return max;
  }
  return parsed;
}

interface WebSearchConfig {
  excludeDomains: string[] | null;
  includeDomains: string[] | null;
  includeText: boolean;
  numResults: number;
  query: string;
}

function parseWebSearchConfig(
  args: Record<string, unknown>
): WebSearchConfig | string {
  const query = extractStringArg(args, ["query", "q", "search", "prompt"]);
  if (!query) {
    return "Error: Missing required parameter 'query'";
  }

  const requestedNumResults = parseBoundedPositiveInt(
    args.num_results ?? args.numResults,
    1,
    WEB_SEARCH_MAX_RESULTS
  );

  return {
    query,
    numResults: requestedNumResults ?? WEB_SEARCH_DEFAULT_RESULTS,
    includeText: args.include_text === true || args.includeText === true,
    includeDomains: extractStringArrayArg(args, [
      "include_domains",
      "includeDomains",
      "domains",
    ]),
    excludeDomains: extractStringArrayArg(args, [
      "exclude_domains",
      "excludeDomains",
    ]),
  };
}

function buildWebSearchBody(config: WebSearchConfig): Record<string, unknown> {
  const body: Record<string, unknown> = {
    query: config.query,
    numResults: config.numResults,
    type: "auto",
  };

  if (config.includeText) {
    body.text = true;
  }
  if (config.includeDomains && config.includeDomains.length > 0) {
    body.includeDomains = config.includeDomains;
  }
  if (config.excludeDomains && config.excludeDomains.length > 0) {
    body.excludeDomains = config.excludeDomains;
  }

  return body;
}

function formatWebSearchError(response: Response, errorText: string): string {
  if (errorText.length === 0) {
    return `Error: web_search failed (${response.status} ${response.statusText})`;
  }
  return truncateOutput(
    `Error: web_search failed (${response.status} ${response.statusText}): ${errorText}`
  );
}

async function fetchWebSearchResults(
  apiKey: string,
  body: Record<string, unknown>
): Promise<unknown | string> {
  let response: Response;
  try {
    response = await fetch(EXA_SEARCH_ENDPOINT, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(WEB_SEARCH_TIMEOUT_MS),
    });
  } catch (err) {
    if (err instanceof Error && err.name === "TimeoutError") {
      return `Error: web_search request timed out after ${WEB_SEARCH_TIMEOUT_MS}ms`;
    }
    return `Error: web_search request failed: ${String(err)}`;
  }

  if (!response.ok) {
    const errorText = (await response.text()).trim();
    return formatWebSearchError(response, errorText);
  }

  try {
    return await response.json();
  } catch (err) {
    return `Error: web_search returned invalid JSON: ${String(err)}`;
  }
}

function appendWebSearchPublishedDate(
  lines: string[],
  result: Record<string, unknown>
): void {
  if (
    typeof result.publishedDate === "string" &&
    result.publishedDate.trim().length > 0
  ) {
    lines.push(`   Published: ${result.publishedDate.trim()}`);
  }
}

function appendWebSearchScore(
  lines: string[],
  result: Record<string, unknown>
): void {
  if (typeof result.score === "number" && Number.isFinite(result.score)) {
    lines.push(`   Score: ${result.score.toFixed(3)}`);
  }
}

function appendWebSearchSnippet(
  lines: string[],
  result: Record<string, unknown>
): void {
  if (typeof result.text !== "string" || result.text.trim().length === 0) {
    return;
  }

  const normalized = result.text.replaceAll(/\s+/g, " ").trim();
  const snippet =
    normalized.length > 400 ? `${normalized.slice(0, 400)}...` : normalized;
  lines.push(`   Snippet: ${snippet}`);
}

function formatWebSearchResultRow(
  result: Record<string, unknown>,
  rank: number,
  includeText: boolean
): string[] | null {
  const title =
    typeof result.title === "string" && result.title.trim().length > 0
      ? result.title.trim()
      : "(untitled)";
  const url =
    typeof result.url === "string" && result.url.trim().length > 0
      ? result.url.trim()
      : "";
  if (!url) {
    return null;
  }

  const lines = [`${rank}. ${title}`, `   URL: ${url}`];
  appendWebSearchPublishedDate(lines, result);
  appendWebSearchScore(lines, result);
  if (includeText) {
    appendWebSearchSnippet(lines, result);
  }
  lines.push("");

  return lines;
}

function formatWebSearchResults(
  results: unknown[],
  query: string,
  includeText: boolean
): string {
  const lines: string[] = [];
  let rank = 1;

  for (const result of results) {
    if (!isRecord(result)) {
      continue;
    }

    const row = formatWebSearchResultRow(result, rank, includeText);
    if (!row) {
      continue;
    }

    lines.push(...row);
    rank += 1;
  }

  if (rank === 1) {
    return `No web results found for '${query}'`;
  }

  return truncateOutput(lines.join("\n").trim());
}

async function webSearch(args: Record<string, unknown>): Promise<string> {
  const config = parseWebSearchConfig(args);
  if (typeof config === "string") {
    return config;
  }

  const apiKey =
    process.env.RUBBER_DUCK_EXA_API_KEY ?? process.env.EXA_API_KEY ?? "";
  if (!apiKey) {
    return "Error: EXA_API_KEY not configured. Set EXA_API_KEY (or RUBBER_DUCK_EXA_API_KEY) to enable web_search.";
  }

  const payload = await fetchWebSearchResults(
    apiKey,
    buildWebSearchBody(config)
  );
  if (typeof payload === "string") {
    return payload;
  }

  if (!(isRecord(payload) && Array.isArray(payload.results))) {
    return "Error: web_search response missing expected 'results' array";
  }

  return formatWebSearchResults(
    payload.results,
    config.query,
    config.includeText
  );
}

// ---------------------------------------------------------------------------
// Main dispatcher
// ---------------------------------------------------------------------------

/**
 * Execute a voice tool by name with JSON-string arguments.
 * Returns a string result suitable for sending back to OpenAI as a tool result.
 */
export async function executeVoiceTool(
  toolName: string,
  argsJson: string,
  workspacePath: string,
  safeMode = false
): Promise<string> {
  let parsedArgs: unknown;
  try {
    parsedArgs = JSON.parse(argsJson);
  } catch {
    return "Error: Invalid JSON arguments";
  }

  const args = normalizeArgs(toolName, parsedArgs);
  if (!args) {
    return "Error: Tool arguments must be a JSON object";
  }

  const workspaceRoot = await resolveWorkspaceRoot(workspacePath);
  if (!workspaceRoot) {
    return `Error: Workspace not accessible: '${workspacePath}'`;
  }

  switch (toolName) {
    case "read_file":
      return readFile(args, workspaceRoot);
    case "write_file":
      return writeFile(args, workspaceRoot, safeMode);
    case "edit_file":
      return editFile(args, workspaceRoot, safeMode);
    case "bash":
      return bash(args, workspaceRoot, safeMode);
    case "grep_search":
      return grepSearch(args, workspaceRoot);
    case "find_files":
      return findFiles(args, workspaceRoot);
    case "web_search":
      return webSearch(args);
    default:
      return `Error: Unknown tool '${toolName}'`;
  }
}
