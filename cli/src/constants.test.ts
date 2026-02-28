import { describe, expect, it } from "vitest";
import { resolveAppSupport } from "./constants.js";

describe("resolveAppSupport", () => {
  it("uses override when provided", () => {
    const resolved = resolveAppSupport({
      env: { RUBBER_DUCK_APP_SUPPORT: " /tmp/custom-duck " },
      exists: () => false,
      homeDir: "/Users/tester",
    });

    expect(resolved).toBe("/tmp/custom-duck");
  });

  it("prefers standard app support path when both standard and legacy exist", () => {
    const standard = "/Users/tester/Library/Application Support/RubberDuck";
    const legacy =
      "/Users/tester/Library/Containers/co.blode.rubber-duck/Data/Library/Application Support/RubberDuck";

    const resolved = resolveAppSupport({
      env: {},
      exists: (path) => path === standard || path === legacy,
      homeDir: "/Users/tester",
    });

    expect(resolved).toBe(standard);
  });

  it("falls back to legacy container path when standard path is missing", () => {
    const legacy =
      "/Users/tester/Library/Containers/co.blode.rubber-duck/Data/Library/Application Support/RubberDuck";

    const resolved = resolveAppSupport({
      env: {},
      exists: (path) => path === legacy,
      homeDir: "/Users/tester",
    });

    expect(resolved).toBe(legacy);
  });
});
