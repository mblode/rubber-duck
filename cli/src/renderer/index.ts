import { createJsonRenderer } from "./json-renderer.js";
import { createTextRenderer } from "./text-renderer.js";
import type { EventRenderer, RendererOptions } from "./types.js";

export function createRenderer(options: RendererOptions): EventRenderer {
  if (options.json) {
    return createJsonRenderer();
  }
  return createTextRenderer(options);
}

export type {
  EventRenderer,
  RendererOptions,
  RendererPiEvent,
} from "./types.js";
