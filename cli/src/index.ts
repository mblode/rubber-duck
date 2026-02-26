// Types

// Client
export { DaemonClient } from "./client.js";
// Constants
export {
  APP_SUPPORT,
  CONFIG_PATH,
  LOG_PATH,
  METADATA_PATH,
  SESSIONS_DIR,
  SOCKET_PATH,
} from "./constants.js";
// Renderer
export { createRenderer } from "./renderer/index.js";
export type {
  EventRenderer,
  RendererOptions,
  RendererPiEvent,
} from "./renderer/types.js";
export type {
  AgentEndEvent,
  AgentMessage,
  AgentStartEvent,
  AssistantMessageDelta,
  AssistantMessageDeltaType,
  AutoCompactionEndEvent,
  AutoCompactionStartEvent,
  AutoRetryEndEvent,
  AutoRetryStartEvent,
  ContentBlock,
  DaemonEvent,
  DaemonMessage,
  DaemonMetadata,
  DaemonMethod,
  DaemonRequest,
  DaemonResponse,
  DoctorCheck,
  ExtensionErrorEvent,
  ExtensionUiRequestEvent,
  ExtensionUiResponsePayload,
  MessageEndEvent,
  MessageStartEvent,
  MessageUpdateEvent,
  PiEvent,
  PiRpcRequest,
  PiRpcResponse,
  PiSessionStats,
  PiState,
  PiToolCall,
  Session,
  ToolContent,
  ToolExecutionEndEvent,
  ToolExecutionStartEvent,
  ToolExecutionUpdateEvent,
  ToolResult,
  TurnEndEvent,
  TurnStartEvent,
  Workspace,
} from "./types.js";
export {
  isDaemonEvent,
  isDaemonResponse,
  isExtensionUiRequestEvent,
} from "./types.js";

// Utilities
export {
  findGitRoot,
  formatTimestamp,
  generateId,
  resolveWorkspacePath,
  workspaceId,
} from "./utils.js";
