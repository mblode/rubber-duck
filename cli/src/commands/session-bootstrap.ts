import type { DaemonClient } from "../client.js";
import type { DaemonResponse } from "../types.js";
import { resolveWorkspacePath } from "../utils.js";

/**
 * Ensure the client is following a session. If no active session exists,
 * auto-attach the current workspace and follow the newly created session.
 *
 * Returns the successful follow response.
 */
export async function ensureFollowing(
  client: DaemonClient,
  sessionId?: string
): Promise<DaemonResponse> {
  let followResp = await client.request("follow", { sessionId });

  if (
    !(followResp.ok || sessionId) &&
    typeof followResp.error === "string" &&
    followResp.error.includes("No active session")
  ) {
    const attachResp = await client.request("attach", {
      path: resolveWorkspacePath(),
    });
    if (!attachResp.ok) {
      return attachResp;
    }

    const attachedSessionId = (attachResp.data as { session: { id: string } })
      .session.id;
    followResp = await client.request("follow", {
      sessionId: attachedSessionId,
    });
  }

  return followResp;
}
