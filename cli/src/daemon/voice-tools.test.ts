import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  afterAll,
  afterEach,
  beforeAll,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest";
import { executeVoiceTool } from "./voice-tools.js";

const ERROR_PREFIX_RE = /^Error:/;
const ERROR_RE = /Error:/;
const WRITTEN_TXT_RE = /written\.txt/;
const FILE_TXT_RE = /file\.txt/;
const EDIT_TARGET_RE = /edit-target\.txt/;
const EXIT_CODE_1_RE = /\[Exit code: 1\]/;
const UNKNOWN_TOOL_RE = /Error: Unknown tool/;
const WEB_SEARCH_TITLE_RE = /OpenAI/;
const WEB_SEARCH_URL_RE = /https:\/\/openai\.com\/news/;

let tmpDir: string;

beforeAll(async () => {
  tmpDir = await mkdtemp(join(tmpdir(), "voice-tools-test-"));
});

afterAll(async () => {
  await rm(tmpDir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// read_file
// ---------------------------------------------------------------------------

describe("read_file", () => {
  it("reads an existing file", async () => {
    const filePath = join(tmpDir, "hello.txt");
    await writeFile(filePath, "hello world");
    const result = await executeVoiceTool(
      "read_file",
      JSON.stringify({ path: "hello.txt" }),
      tmpDir
    );
    expect(result).toBe("hello world");
  });

  it("returns error for missing file", async () => {
    const result = await executeVoiceTool(
      "read_file",
      JSON.stringify({ path: "does-not-exist.txt" }),
      tmpDir
    );
    expect(result).toMatch(ERROR_PREFIX_RE);
  });

  it("rejects path traversal outside workspace", async () => {
    const result = await executeVoiceTool(
      "read_file",
      JSON.stringify({ path: "../../etc/passwd" }),
      tmpDir
    );
    expect(result).toMatch(ERROR_RE);
  });

  it("accepts common path aliases", async () => {
    const filePath = join(tmpDir, "alias.txt");
    await writeFile(filePath, "alias content");
    const result = await executeVoiceTool(
      "read_file",
      JSON.stringify({ filepath: "alias.txt" }),
      tmpDir
    );
    expect(result).toBe("alias content");
  });

  it("accepts bare string JSON arguments for read_file", async () => {
    const filePath = join(tmpDir, "bare-string.txt");
    await writeFile(filePath, "string arg content");
    const result = await executeVoiceTool(
      "read_file",
      JSON.stringify("bare-string.txt"),
      tmpDir
    );
    expect(result).toBe("string arg content");
  });
});

// ---------------------------------------------------------------------------
// write_file
// ---------------------------------------------------------------------------

describe("write_file", () => {
  it("writes a new file", async () => {
    const result = await executeVoiceTool(
      "write_file",
      JSON.stringify({ path: "written.txt", content: "written content" }),
      tmpDir
    );
    expect(result).toMatch(WRITTEN_TXT_RE);

    const check = await executeVoiceTool(
      "read_file",
      JSON.stringify({ path: "written.txt" }),
      tmpDir
    );
    expect(check).toBe("written content");
  });

  it("creates parent directories automatically", async () => {
    const result = await executeVoiceTool(
      "write_file",
      JSON.stringify({ path: "subdir/nested/file.txt", content: "deep" }),
      tmpDir
    );
    expect(result).toMatch(FILE_TXT_RE);
  });
});

// ---------------------------------------------------------------------------
// edit_file
// ---------------------------------------------------------------------------

describe("edit_file", () => {
  beforeEach(async () => {
    await writeFile(join(tmpDir, "edit-target.txt"), "foo bar baz");
  });

  it("replaces matching text", async () => {
    const result = await executeVoiceTool(
      "edit_file",
      JSON.stringify({
        path: "edit-target.txt",
        old_text: "bar",
        new_text: "qux",
      }),
      tmpDir
    );
    expect(result).toMatch(EDIT_TARGET_RE);

    const check = await executeVoiceTool(
      "read_file",
      JSON.stringify({ path: "edit-target.txt" }),
      tmpDir
    );
    expect(check).toBe("foo qux baz");
  });

  it("errors when old_text not found", async () => {
    const result = await executeVoiceTool(
      "edit_file",
      JSON.stringify({
        path: "edit-target.txt",
        old_text: "NOTPRESENT",
        new_text: "x",
      }),
      tmpDir
    );
    expect(result).toMatch(ERROR_RE);
  });

  it("errors when old_text appears multiple times", async () => {
    await writeFile(join(tmpDir, "dup.txt"), "aaa aaa");
    const result = await executeVoiceTool(
      "edit_file",
      JSON.stringify({ path: "dup.txt", old_text: "aaa", new_text: "bbb" }),
      tmpDir
    );
    expect(result).toMatch(ERROR_RE);
  });
});

// ---------------------------------------------------------------------------
// find_files
// ---------------------------------------------------------------------------

describe("find_files", () => {
  beforeAll(async () => {
    const findDir = join(tmpDir, "findtest");
    await mkdir(findDir, { recursive: true });
    await mkdir(join(findDir, "nested"), { recursive: true });
    await writeFile(join(findDir, "alpha.ts"), "");
    await writeFile(join(findDir, "beta.ts"), "");
    await writeFile(join(findDir, "nested", "delta.ts"), "");
    await writeFile(join(findDir, ".secret.ts"), "");
    await writeFile(join(findDir, "gamma.txt"), "");
  });

  it("matches glob pattern", async () => {
    const result = await executeVoiceTool(
      "find_files",
      JSON.stringify({ pattern: "**/*.ts", path: "findtest" }),
      tmpDir
    );
    expect(result).toContain("alpha.ts");
    expect(result).toContain("beta.ts");
    expect(result).toContain("nested/delta.ts");
    expect(result).not.toContain("gamma.txt");
  });

  it("returns sorted output", async () => {
    const result = await executeVoiceTool(
      "find_files",
      JSON.stringify({ pattern: "**/*.ts", path: "findtest" }),
      tmpDir
    );
    const lines = result
      .split("\n")
      .filter((line) => line.length > 0 && !line.startsWith("["));
    expect(lines).toEqual([...lines].sort());
  });

  it("excludes hidden files by default", async () => {
    const result = await executeVoiceTool(
      "find_files",
      JSON.stringify({ pattern: "**/*.ts", path: "findtest" }),
      tmpDir
    );
    expect(result).not.toContain(".secret.ts");
  });

  it("includes hidden files when requested", async () => {
    const result = await executeVoiceTool(
      "find_files",
      JSON.stringify({
        pattern: "**/*.ts",
        path: "findtest",
        include_hidden: true,
      }),
      tmpDir
    );
    expect(result).toContain(".secret.ts");
  });

  it("returns files only by default", async () => {
    const result = await executeVoiceTool(
      "find_files",
      JSON.stringify({ pattern: "*", path: "findtest" }),
      tmpDir
    );
    const lines = result.split("\n").filter((line) => line.length > 0);
    expect(lines).not.toContain("findtest/nested");
    expect(lines).toContain("findtest/nested/delta.ts");
  });

  it("includes directories when requested", async () => {
    const result = await executeVoiceTool(
      "find_files",
      JSON.stringify({
        pattern: "*",
        path: "findtest",
        include_directories: true,
      }),
      tmpDir
    );
    expect(result).toContain("findtest/nested");
  });

  it("returns explicit error when search path does not exist", async () => {
    const result = await executeVoiceTool(
      "find_files",
      JSON.stringify({ pattern: "*", path: "missing-directory" }),
      tmpDir
    );
    expect(result).toContain("Error: Search path not found");
  });

  it("returns explicit error when search path is a file", async () => {
    await writeFile(join(tmpDir, "single-file.txt"), "x");
    const result = await executeVoiceTool(
      "find_files",
      JSON.stringify({ pattern: "*", path: "single-file.txt" }),
      tmpDir
    );
    expect(result).toContain("Error: Search path is not a directory");
  });

  it("returns error for invalid JSON", async () => {
    const result = await executeVoiceTool("find_files", "{invalid}", tmpDir);
    expect(result).toMatch(ERROR_RE);
  });
});

// ---------------------------------------------------------------------------
// web_search
// ---------------------------------------------------------------------------

describe("web_search", () => {
  let previousExaKey: string | undefined;
  let previousRubberDuckExaKey: string | undefined;

  beforeEach(() => {
    previousExaKey = process.env.EXA_API_KEY;
    previousRubberDuckExaKey = process.env.RUBBER_DUCK_EXA_API_KEY;
    process.env.EXA_API_KEY = undefined;
    process.env.RUBBER_DUCK_EXA_API_KEY = undefined;
    vi.restoreAllMocks();
  });

  afterEach(() => {
    if (previousExaKey === undefined) {
      process.env.EXA_API_KEY = undefined;
    } else {
      process.env.EXA_API_KEY = previousExaKey;
    }

    if (previousRubberDuckExaKey === undefined) {
      process.env.RUBBER_DUCK_EXA_API_KEY = undefined;
    } else {
      process.env.RUBBER_DUCK_EXA_API_KEY = previousRubberDuckExaKey;
    }

    vi.restoreAllMocks();
  });

  it("returns a clear error when EXA key is missing", async () => {
    const result = await executeVoiceTool(
      "web_search",
      JSON.stringify({ query: "OpenAI announcements" }),
      tmpDir
    );
    expect(result).toContain("EXA_API_KEY not configured");
  });

  it("queries Exa and formats result rows", async () => {
    process.env.EXA_API_KEY = "test-exa-key";
    const fetchMock = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          results: [
            {
              title: "OpenAI News",
              url: "https://openai.com/news",
              publishedDate: "2026-02-15",
              score: 0.9876,
              text: "Latest updates from OpenAI about models, APIs, and platform features.",
            },
          ],
        }),
        {
          status: 200,
          headers: { "content-type": "application/json" },
        }
      )
    );

    const result = await executeVoiceTool(
      "web_search",
      JSON.stringify({
        query: "latest OpenAI announcements",
        num_results: 3,
        include_text: true,
      }),
      tmpDir
    );

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(result).toMatch(WEB_SEARCH_TITLE_RE);
    expect(result).toMatch(WEB_SEARCH_URL_RE);
    expect(result).toContain("Published: 2026-02-15");
    expect(result).toContain("Snippet:");
  });
});

// ---------------------------------------------------------------------------
// grep_search
// ---------------------------------------------------------------------------

describe("grep_search", () => {
  beforeAll(async () => {
    const grepDir = join(tmpDir, "greptest");
    await mkdir(grepDir, { recursive: true });
    await writeFile(
      join(grepDir, "source.ts"),
      'const x = "hello";\nconst y = "world";'
    );
  });

  it("finds matching lines", async () => {
    const result = await executeVoiceTool(
      "grep_search",
      JSON.stringify({ pattern: "hello", path: "greptest" }),
      tmpDir
    );
    expect(result).toContain("hello");
  });

  it("returns no matches message when pattern not found", async () => {
    const result = await executeVoiceTool(
      "grep_search",
      JSON.stringify({ pattern: "ZZZNOMATCH", path: "greptest" }),
      tmpDir
    );
    expect(result).toBe("No matches found");
  });
});

// ---------------------------------------------------------------------------
// bash
// ---------------------------------------------------------------------------

describe("bash", () => {
  it("executes a command and returns stdout", async () => {
    const result = await executeVoiceTool(
      "bash",
      JSON.stringify({ command: "echo hello" }),
      tmpDir
    );
    expect(result).toContain("hello");
  });

  it("returns exit code on failure", async () => {
    const result = await executeVoiceTool(
      "bash",
      JSON.stringify({ command: "exit 1" }),
      tmpDir
    );
    expect(result).toMatch(EXIT_CODE_1_RE);
  });

  it("rejects unknown tool names", async () => {
    const result = await executeVoiceTool(
      "unknown_tool",
      JSON.stringify({}),
      tmpDir
    );
    expect(result).toMatch(UNKNOWN_TOOL_RE);
  });
});
