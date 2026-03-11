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
  AgentEndEvent,
  AgentMessage,
  AgentStartEvent,
  AppHistoryEvent,
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
  DaemonRequestMap,
  DaemonResponse,
  DoctorCheck,
  EventRenderer,
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
  RemoteControlStatus,
  RendererOptions,
  RendererPiEvent,
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
