import { log } from "@clack/prompts";
import type { DaemonClient } from "../client.js";
import { handleUiRequest } from "../renderer/ui-handler.js";
import type { DaemonEvent } from "../types.js";
import { isExtensionUiRequestEvent } from "../types.js";

interface HandleUiEventOptions {
  interactive: boolean;
}

export function handleUiEvent(
  event: DaemonEvent,
  client: DaemonClient,
  options: HandleUiEventOptions
): void {
  if (!isExtensionUiRequestEvent(event.data)) {
    return;
  }

  handleUiRequest(
    event.data,
    {
      send: (response) => {
        client
          .request("extension_ui_response", {
            ...response,
            sessionId: event.sessionId,
          })
          .catch((err) => {
            log.warn(
              `UI response failed: ${err instanceof Error ? err.message : String(err)}`
            );
          });
      },
    },
    options.interactive
  ).catch((err) => {
    log.warn(
      `UI prompt failed: ${err instanceof Error ? err.message : String(err)}`
    );
  });
}
