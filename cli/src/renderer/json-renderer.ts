import type { EventRenderer, RendererPiEvent } from "../types.js";

export function createJsonRenderer(): EventRenderer {
  return {
    render(event: RendererPiEvent): void {
      process.stdout.write(`${JSON.stringify(event)}\n`);
    },
    cleanup(): void {
      // No state to clean up in JSON mode
    },
  };
}
