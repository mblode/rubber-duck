import { confirm, isCancel, select, text } from "@clack/prompts";
import type { ExtensionUiRequestEvent } from "../types.js";

interface UiResponseSender {
  send(response: {
    cancelled?: boolean;
    confirmed?: boolean;
    id: string;
    value?: unknown;
  }): void;
}

export async function handleUiRequest(
  event: ExtensionUiRequestEvent,
  sender: UiResponseSender,
  interactive: boolean
): Promise<void> {
  switch (event.method) {
    case "notify":
    case "setStatus":
    case "setWidget":
    case "setTitle":
    case "set_editor_text":
      // Fire-and-forget — no response needed
      return;

    case "confirm":
      await handleConfirm(event, sender, interactive);
      return;

    case "select":
      await handleSelect(event, sender, interactive);
      return;

    case "input":
      await handleInput(event, sender, interactive);
      return;

    case "editor":
      await handleInput(event, sender, interactive);
      return;

    default:
      break;
  }
}

async function handleConfirm(
  event: ExtensionUiRequestEvent,
  sender: UiResponseSender,
  interactive: boolean
): Promise<void> {
  if (!interactive) {
    sender.send({
      id: event.id,
      cancelled: true,
    });
    return;
  }

  const result = await confirm({
    message: event.title ?? event.message ?? "Confirm?",
  });

  if (isCancel(result)) {
    sender.send({
      id: event.id,
      cancelled: true,
    });
    return;
  }

  sender.send({
    id: event.id,
    confirmed: result,
  });
}

async function handleSelect(
  event: ExtensionUiRequestEvent,
  sender: UiResponseSender,
  interactive: boolean
): Promise<void> {
  if (!(interactive && event.options?.length)) {
    sender.send({
      id: event.id,
      cancelled: true,
    });
    return;
  }

  const result = await select({
    message: event.title ?? event.message ?? "Select an option",
    options: event.options.map((opt) => ({
      value: typeof opt === "string" ? opt : opt.value,
      label: typeof opt === "string" ? opt : opt.label,
    })),
  });

  if (isCancel(result)) {
    sender.send({
      id: event.id,
      cancelled: true,
    });
    return;
  }

  sender.send({
    id: event.id,
    value: result,
  });
}

async function handleInput(
  event: ExtensionUiRequestEvent,
  sender: UiResponseSender,
  interactive: boolean
): Promise<void> {
  if (!interactive) {
    sender.send({
      id: event.id,
      cancelled: true,
    });
    return;
  }

  const result = await text({
    message: event.title ?? event.message ?? "Enter a value",
    placeholder: event.placeholder,
    defaultValue: event.prefill,
  });

  if (isCancel(result)) {
    sender.send({
      id: event.id,
      cancelled: true,
    });
    return;
  }

  sender.send({
    id: event.id,
    value: result,
  });
}
