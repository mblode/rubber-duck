export class ToolTracker {
  private readonly seen = new Map<string, number>();

  getNewOutput(toolCallId: string, accumulated: string): string {
    const offset = this.seen.get(toolCallId) ?? 0;
    const newContent = accumulated.slice(offset);
    this.seen.set(toolCallId, accumulated.length);
    return newContent;
  }

  complete(toolCallId: string): void {
    this.seen.delete(toolCallId);
  }

  reset(): void {
    this.seen.clear();
  }
}
