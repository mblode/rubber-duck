import type { EventRenderer, RendererOptions } from "../types.js";
import { createJsonRenderer } from "./json-renderer.js";
import { createTextRenderer } from "./text-renderer.js";

export function createRenderer(options: RendererOptions): EventRenderer {
  if (options.json) {
    return createJsonRenderer();
  }
  return createTextRenderer(options);
}
