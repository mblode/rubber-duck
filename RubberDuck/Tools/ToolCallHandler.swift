import Foundation

@MainActor
class ToolCallHandler {
    private let toolExecutor: ToolExecutor
    private let realtimeClient: RealtimeClient

    init(toolExecutor: ToolExecutor, realtimeClient: RealtimeClient) {
        self.toolExecutor = toolExecutor
        self.realtimeClient = realtimeClient
    }

    func setSafeMode(_ enabled: Bool) {
        toolExecutor.safeMode = enabled
    }

    func handleFunctionCalls(_ calls: [(callId: String, name: String, arguments: String)],
                             onToolStart: ((String) -> Void)? = nil,
                             completion: @escaping () -> Void) {
        Task {
            for call in calls {
                onToolStart?(call.name)
                logInfo("ToolCallHandler: Executing \(call.name) (callId: \(call.callId))")

                let result = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = self.toolExecutor.execute(toolName: call.name, arguments: call.arguments)
                        continuation.resume(returning: result)
                    }
                }

                logInfo("ToolCallHandler: \(call.name) completed (\(result.count) chars)")
                realtimeClient.sendToolResult(callId: call.callId, output: result)
            }
            completion()
        }
    }
}
