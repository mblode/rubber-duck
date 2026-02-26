// ---------------------------------------------------------------------------
// Renderer-specific Pi Event Types
// Self-contained to avoid coupling with the main types.ts during development.
// ---------------------------------------------------------------------------

export interface PiEventBase {
  type: string;
}

export interface AgentStartEvent extends PiEventBase {
  type: "agent_start";
}

export interface AgentEndEvent extends PiEventBase {
  messages: unknown[];
  type: "agent_end";
}

export interface TurnStartEvent extends PiEventBase {
  type: "turn_start";
}

export interface TurnEndEvent extends PiEventBase {
  type: "turn_end";
}

export interface MessageStartEvent extends PiEventBase {
  message: AgentMessage;
  type: "message_start";
}

export interface MessageUpdateEvent extends PiEventBase {
  assistantMessageEvent: AssistantMessageDelta;
  message: AgentMessage;
  type: "message_update";
}

export interface MessageEndEvent extends PiEventBase {
  message: AgentMessage;
  type: "message_end";
}

export interface ToolExecutionStartEvent extends PiEventBase {
  args: Record<string, unknown>;
  toolCallId: string;
  toolName: string;
  type: "tool_execution_start";
}

export interface ToolExecutionUpdateEvent extends PiEventBase {
  args: Record<string, unknown>;
  partialResult: ToolContent;
  toolCallId: string;
  toolName: string;
  type: "tool_execution_update";
}

export interface ToolExecutionEndEvent extends PiEventBase {
  exitCode?: number;
  isError: boolean;
  result: ToolContent;
  toolCallId: string;
  toolName: string;
  type: "tool_execution_end";
}

export interface AutoCompactionStartEvent extends PiEventBase {
  reason: "threshold" | "overflow";
  type: "auto_compaction_start";
}

export interface AutoCompactionEndEvent extends PiEventBase {
  aborted: boolean;
  errorMessage?: string;
  result: { summary: string; tokensBefore: number } | null;
  type: "auto_compaction_end";
  willRetry: boolean;
}

export interface AutoRetryStartEvent extends PiEventBase {
  attempt: number;
  delayMs: number;
  errorMessage: string;
  maxAttempts: number;
  type: "auto_retry_start";
}

export interface AutoRetryEndEvent extends PiEventBase {
  attempt: number;
  finalError?: string;
  success: boolean;
  type: "auto_retry_end";
}

export interface ExtensionErrorEvent extends PiEventBase {
  error: string;
  event: string;
  extensionPath: string;
  type: "extension_error";
}

export interface ExtensionUiRequestEvent extends PiEventBase {
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

export type RendererPiEvent =
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
  type: AssistantMessageDeltaType;
}

export interface AgentMessage {
  content?: string | ContentBlock[];
  id?: string;
  role: string;
  timestamp?: string;
}

export interface ContentBlock {
  text?: string;
  type: string;
}

export interface ToolContent {
  content: Array<{ type: string; text?: string }>;
  details?: { truncation?: string; fullOutputPath?: string };
}

// ---------------------------------------------------------------------------
// Renderer Interfaces
// ---------------------------------------------------------------------------

export interface EventRenderer {
  cleanup(): void;
  render(event: RendererPiEvent): void | Promise<void>;
}

export interface RendererOptions {
  color: boolean;
  json: boolean;
  showThinking: boolean;
  verbose: boolean;
}
