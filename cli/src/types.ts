// ---------------------------------------------------------------------------
// Pi RPC Types
// ---------------------------------------------------------------------------

export interface PiRpcRequest {
  id?: string;
  type: string;
  [key: string]: unknown;
}

export interface PiRpcResponse {
  command?: string;
  data?: Record<string, unknown>;
  error?: string;
  id?: string;
  success: boolean;
  type: "response";
}

// ---------------------------------------------------------------------------
// Pi Event Types
// ---------------------------------------------------------------------------

export interface AgentStartEvent {
  type: "agent_start";
}

export interface AgentEndEvent {
  messages: unknown[];
  type: "agent_end";
}

export interface TurnStartEvent {
  type: "turn_start";
}

export interface TurnEndEvent {
  message: AgentMessage;
  toolResults: ToolResult[];
  type: "turn_end";
}

export interface MessageStartEvent {
  message: AgentMessage;
  type: "message_start";
}

export interface MessageUpdateEvent {
  assistantMessageEvent: AssistantMessageDelta;
  message: AgentMessage;
  type: "message_update";
}

export interface MessageEndEvent {
  message: AgentMessage;
  type: "message_end";
}

export interface ToolExecutionStartEvent {
  args: Record<string, unknown>;
  toolCallId: string;
  toolName: string;
  type: "tool_execution_start";
}

export interface ToolExecutionUpdateEvent {
  args: Record<string, unknown>;
  partialResult: ToolContent;
  toolCallId: string;
  toolName: string;
  type: "tool_execution_update";
}

export interface ToolExecutionEndEvent {
  exitCode?: number;
  isError: boolean;
  result: ToolContent;
  toolCallId: string;
  toolName: string;
  type: "tool_execution_end";
}

export interface AutoCompactionStartEvent {
  reason: "threshold" | "overflow";
  type: "auto_compaction_start";
}

export interface AutoCompactionEndEvent {
  aborted: boolean;
  errorMessage?: string;
  result: { summary: string; tokensBefore: number } | null;
  type: "auto_compaction_end";
  willRetry: boolean;
}

export interface AutoRetryStartEvent {
  attempt: number;
  delayMs: number;
  errorMessage: string;
  maxAttempts: number;
  type: "auto_retry_start";
}

export interface AutoRetryEndEvent {
  attempt: number;
  finalError?: string;
  success: boolean;
  type: "auto_retry_end";
}

export interface ExtensionErrorEvent {
  error: string;
  event: string;
  extensionPath: string;
  type: "extension_error";
}

export interface ExtensionUiRequestEvent {
  id: string;
  message?: string;
  method:
    | "select"
    | "confirm"
    | "input"
    | "editor"
    | "notify"
    | "setStatus"
    | "setWidget"
    | "setTitle"
    | "set_editor_text";
  notifyType?: "info" | "warning" | "error";
  options?: Array<string | { label: string; value: string }>;
  placeholder?: string;
  prefill?: string;
  timeout?: number;
  title?: string;
  type: "extension_ui_request";
}

export interface ExtensionUiResponsePayload {
  cancelled?: boolean;
  confirmed?: boolean;
  id: string;
  value?: unknown;
}

export type PiEvent =
  | AgentStartEvent
  | AgentEndEvent
  | TurnStartEvent
  | TurnEndEvent
  | MessageStartEvent
  | MessageUpdateEvent
  | MessageEndEvent
  | ToolExecutionStartEvent
  | ToolExecutionUpdateEvent
  | ToolExecutionEndEvent
  | AutoCompactionStartEvent
  | AutoCompactionEndEvent
  | AutoRetryStartEvent
  | AutoRetryEndEvent
  | ExtensionErrorEvent
  | ExtensionUiRequestEvent;

// ---------------------------------------------------------------------------
// Supporting Types
// ---------------------------------------------------------------------------

export type AssistantMessageDeltaType =
  | "start"
  | "text_start"
  | "text_delta"
  | "text_end"
  | "thinking_start"
  | "thinking_delta"
  | "thinking_end"
  | "toolcall_start"
  | "toolcall_delta"
  | "toolcall_end"
  | "done"
  | "error";

export interface AssistantMessageDelta {
  contentIndex?: number;
  delta?: string;
  partial?: unknown;
  reason?: string;
  toolCall?: PiToolCall;
  type: AssistantMessageDeltaType;
}

export interface PiToolCall {
  arguments: string;
  id: string;
  name: string;
}

export interface AgentMessage {
  content?: string | ContentBlock[];
  id?: string;
  role:
    | "user"
    | "assistant"
    | "toolResult"
    | "bashExecution"
    | "custom"
    | "branchSummary"
    | "compactionSummary";
  timestamp?: string;
}

export interface ContentBlock {
  id?: string;
  input?: Record<string, unknown>;
  name?: string;
  text?: string;
  type: "text" | "tool_use" | "tool_result" | "thinking";
}

export interface ToolContent {
  content: Array<{ type: string; text?: string }>;
  details?: { truncation?: string; fullOutputPath?: string };
}

export interface ToolResult {
  content: Array<{ type: string; text?: string }>;
  isError: boolean;
  toolCallId: string;
  toolName: string;
}

// ---------------------------------------------------------------------------
// Pi State Types
// ---------------------------------------------------------------------------

export interface PiState {
  autoCompactionEnabled: boolean;
  isCompacting: boolean;
  isStreaming: boolean;
  messageCount: number;
  model: string;
  pendingMessageCount: number;
  sessionFile: string;
  sessionId: string;
  sessionName: string;
  thinkingLevel: string;
}

export interface PiSessionStats {
  assistantMessages: number;
  cost: number;
  sessionFile: string;
  sessionId: string;
  tokens: {
    input: number;
    output: number;
    cacheRead: number;
    cacheWrite: number;
    total: number;
  };
  toolCalls: number;
  toolResults: number;
  totalMessages: number;
  userMessages: number;
}

// ---------------------------------------------------------------------------
// Daemon-CLI IPC Protocol
// ---------------------------------------------------------------------------

export type DaemonMethod =
  | "attach"
  | "follow"
  | "unfollow"
  | "extension_ui_response"
  | "say"
  | "sessions"
  | "use"
  | "new"
  | "abort"
  | "doctor"
  | "export"
  | "get_state"
  | "ping";

export interface DaemonRequest {
  id: string;
  method: DaemonMethod;
  params: Record<string, unknown>;
}

export interface DaemonResponse {
  data?: Record<string, unknown>;
  error?: string;
  id: string;
  ok: boolean;
}

export interface DaemonEvent {
  data: PiEvent | Record<string, unknown>;
  event: string;
  sessionId: string;
}

export type DaemonMessage = DaemonResponse | DaemonEvent;

export function isDaemonResponse(msg: DaemonMessage): msg is DaemonResponse {
  return "id" in msg && "ok" in msg;
}

export function isDaemonEvent(msg: DaemonMessage): msg is DaemonEvent {
  return "event" in msg && "sessionId" in msg;
}

export function isExtensionUiRequestEvent(
  event: PiEvent | Record<string, unknown>
): event is ExtensionUiRequestEvent {
  return (
    typeof event === "object" &&
    event !== null &&
    "type" in event &&
    event.type === "extension_ui_request" &&
    "id" in event
  );
}

// ---------------------------------------------------------------------------
// Domain Model
// ---------------------------------------------------------------------------

export interface Workspace {
  createdAt: string;
  id: string;
  lastActiveSessionId: string | null;
  path: string;
}

export interface Session {
  createdAt: string;
  id: string;
  isVoiceActive: boolean;
  lastActiveAt: string;
  name: string;
  piSessionFile: string;
  workspaceId: string;
}

export interface DaemonMetadata {
  activeVoiceSessionId: string | null;
  sessions: Session[];
  version: number;
  workspaces: Workspace[];
}

export interface DoctorCheck {
  message: string;
  name: string;
  status: "ok" | "warn" | "fail";
}
