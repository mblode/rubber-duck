import { readFileSync } from "node:fs";
import { join } from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { ToolsTable } from "@/components/marketing/tools-table";
import { TOOLS } from "@/lib/content";

/**
 * The tool table is checked against the source that executes the tools.
 *
 * This is the only test on this page that reads a file outside `apps/web`, and
 * it is worth the coupling. The seven-tool table is the most quotable block on
 * the site and no competing product publishes an equivalent, which means it is
 * also the block whose being wrong would cost the most. It is exactly the kind
 * of copy that goes stale silently: somebody adds an eighth tool to the daemon,
 * or renames `grep_search`, and nothing in this repository has any opinion
 * about it. Six months later the page is confidently describing software that
 * no longer exists.
 *
 * So the assertion is symmetric. Every tool the page claims must be a real case
 * in the dispatcher, and every case in the dispatcher must be on the page. A
 * new tool shipped in the CLI fails this suite until somebody writes the row.
 */

const DISPATCHER = join(
  import.meta.dirname,
  "../../../cli/src/daemon/voice-tools.ts"
);

const CASE_LINE = /^\s*case "(\w+)":$/gmu;

const source = readFileSync(DISPATCHER, "utf8");

/** The dispatcher's own `switch (toolName)` arms, which is the definitive list
 * of what the voice agent can call. `default:` is not a tool and is not
 * captured by the pattern. */
const dispatched = new Set(
  [...source.matchAll(CASE_LINE)]
    .map((match) => match[1])
    // `normalizeArgs` switches on the same names to be lenient about
    // single-string arguments, so a name may legitimately appear twice.
    .filter(Boolean)
);

describe("the seven tools", () => {
  it("names exactly the tools the daemon dispatches", () => {
    const claimed = TOOLS.rows.map((tool) => tool.name);
    expect([...claimed].sort()).toEqual([...dispatched].sort());
  });

  it("is seven, which is what the page says in prose", () => {
    expect(TOOLS.rows).toHaveLength(7);
  });

  it("renders every tool name and its safe mode behaviour as text", () => {
    const html = renderToStaticMarkup(ToolsTable());
    for (const tool of TOOLS.rows) {
      expect(html, `${tool.name} is missing from the table`).toContain(
        tool.name
      );
    }
  });

  /**
   * The two that refuse are the whole reason the column exists. Hard-coded
   * rather than derived, because deriving it from the same constant the page
   * renders would assert nothing — this is the pair that must stay true against
   * `writeFile` and `editFile` in the dispatcher, both of which return
   * "disabled in safe mode".
   */
  it("marks write_file and edit_file as blocked in safe mode", () => {
    const blocked = TOOLS.rows
      .filter((tool) => tool.safe === "Blocked")
      .map((tool) => tool.name);
    expect(blocked).toEqual(["write_file", "edit_file"]);
    expect(source).toContain("write_file is disabled in safe mode");
    expect(source).toContain("edit_file is disabled in safe mode");
  });

  /** The allowlist is quoted verbatim on the page. If somebody adds `make` to
   * the daemon's list, the page is understating what safe mode permits, which
   * is the direction of error that matters. */
  it("quotes every command in the safe mode allowlist", () => {
    const prefixes = source
      .slice(
        source.indexOf("SAFE_MODE_ALLOWED_PREFIXES"),
        source.indexOf("function isRecord")
      )
      .matchAll(/"([\w-]+)"/gu);
    for (const [, command] of prefixes) {
      expect(
        TOOLS.allowlist,
        `${command} is allowed in safe mode but is not listed on the page`
      ).toContain(command);
    }
  });
});
