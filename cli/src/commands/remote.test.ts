import { describe, expect, it } from "vitest";
import { normalizePublicUrl } from "./remote.js";

describe("normalizePublicUrl", () => {
  it("accepts bare hostnames and defaults to the remote port", () => {
    expect(normalizePublicUrl("linktree")).toBe("http://linktree:43111");
  });

  it("accepts bare IP addresses and defaults to the remote port", () => {
    expect(normalizePublicUrl("100.96.185.34")).toBe(
      "http://100.96.185.34:43111"
    );
  });

  it("defaults ts.net hosts to https", () => {
    expect(normalizePublicUrl("linktree.example.ts.net")).toBe(
      "https://linktree.example.ts.net"
    );
  });
});
