import { log } from "@clack/prompts";
import type { DaemonClient } from "../client.js";
import type { EventRenderer } from "../types.js";

interface StreamLifecycleOptions {
  /** If true, send an "abort" request on SIGINT before closing. */
  abortOnInterrupt?: boolean;
  /** Extra cleanup to run before closing (e.g. stopAppHistory, clearTimeout). */
  onCleanup?: () => void;
  /** If true, send an "unfollow" request on cleanup. */
  unfollowOnCleanup?: boolean;
}

interface StreamLifecycle {
  /** Trigger a graceful shutdown (idempotent). */
  cleanup: () => void;
}

/**
 * Consolidates SIGINT/SIGTERM handling, connection-loss polling,
 * and renderer/client teardown shared by follow.ts and say.ts.
 */
export function createStreamLifecycle(
  client: DaemonClient,
  renderer: EventRenderer,
  options: StreamLifecycleOptions = {}
): StreamLifecycle {
  let isCleaningUp = false;
  let checkConnection: ReturnType<typeof setInterval> | null = null;

  const cleanup = () => {
    if (isCleaningUp) {
      return;
    }
    isCleaningUp = true;

    if (checkConnection) {
      clearInterval(checkConnection);
      checkConnection = null;
    }

    options.onCleanup?.();
    renderer.cleanup();

    if (options.unfollowOnCleanup) {
      try {
        client.request("unfollow", {}).catch(() => {
          // Best-effort cleanup on shutdown.
        });
      } catch {
        // Best-effort cleanup on shutdown.
      }
    }

    setTimeout(() => {
      client.close();
      process.exit(0);
    }, 100);
  };

  const handleInterrupt = () => {
    if (options.abortOnInterrupt) {
      client.request("abort", {}).catch(() => {
        // Best-effort abort on interrupt.
      });
    }
    cleanup();
  };

  process.once("SIGINT", handleInterrupt);
  process.once("SIGTERM", cleanup);

  checkConnection = setInterval(() => {
    if (!client.isConnected()) {
      if (checkConnection) {
        clearInterval(checkConnection);
        checkConnection = null;
      }
      options.onCleanup?.();
      renderer.cleanup();
      log.error("Daemon disconnected.");
      process.exit(1);
    }
  }, 1000);

  return { cleanup };
}
