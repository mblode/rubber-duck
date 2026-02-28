import Foundation

/// Protocol for sending tool results back to the Realtime API.
/// RealtimeClientProtocol inherits from this, so any RealtimeClientProtocol
/// conformer can be used where ToolResultSending is expected.
protocol ToolResultSending: AnyObject {
    func sendToolResult(callId: String, output: String)
    func requestModelResponse()
}

@MainActor
class ToolOrchestrator {
    private let toolExecutor: ToolExecutor
    private let resultSender: ToolResultSending

    init(toolExecutor: ToolExecutor, resultSender: ToolResultSending) {
        self.toolExecutor = toolExecutor
        self.resultSender = resultSender
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
                logInfo("ToolOrchestrator: Executing \(call.name) (callId: \(call.callId))")

                let result = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = self.toolExecutor.execute(toolName: call.name, arguments: call.arguments)
                        continuation.resume(returning: result)
                    }
                }

                logInfo("ToolOrchestrator: \(call.name) completed (\(result.count) chars)")
                resultSender.sendToolResult(callId: call.callId, output: result)
            }
            resultSender.requestModelResponse()
            completion()
        }
    }
}
