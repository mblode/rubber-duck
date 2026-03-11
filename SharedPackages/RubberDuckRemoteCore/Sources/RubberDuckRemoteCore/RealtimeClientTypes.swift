import Foundation

public enum RealtimeConnectionState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

public enum RealtimeTurnDetectionMode: Sendable {
    case manual
    case semanticVAD
}

public enum RealtimeErrorRetryDisposition: String, Sendable {
    case retryable
    case nonRetryable
}

public struct RealtimeErrorClassification: Sendable {
    public let type: String
    public let code: String
    public let message: String
    public let param: String?
    public let eventId: String?
    public let disposition: RealtimeErrorRetryDisposition

    public init(
        type: String,
        code: String,
        message: String,
        param: String?,
        eventId: String?,
        disposition: RealtimeErrorRetryDisposition
    ) {
        self.type = type
        self.code = code
        self.message = message
        self.param = param
        self.eventId = eventId
        self.disposition = disposition
    }
}

public func classifyRealtimeErrorPayload(
    _ payload: [String: Any]
) -> RealtimeErrorClassification {
    let rawType = (payload["type"] as? String) ?? "unknown_error"
    let rawCode = (payload["code"] as? String) ?? ""
    let rawMessage = (payload["message"] as? String) ?? "Unknown error"
    let param = payload["param"] as? String
    let eventId = payload["event_id"] as? String

    let type = rawType.lowercased()
    let code = rawCode.lowercased()
    let message = rawMessage.lowercased()

    let nonRetryableTypes: Set<String> = [
        "invalid_request_error",
        "authentication_error",
        "permission_error",
        "not_found_error",
        "conflict_error"
    ]
    let nonRetryableCodes: Set<String> = [
        "invalid_api_key",
        "invalid_request",
        "invalid_value",
        "invalid_model",
        "model_not_found",
        "unsupported_voice",
        "unknown_tool",
        "insufficient_quota"
    ]
    let retryableTypes: Set<String> = [
        "server_error",
        "rate_limit_error",
        "overloaded_error",
        "timeout_error"
    ]
    let retryableCodes: Set<String> = [
        "server_error",
        "internal_server_error",
        "service_unavailable",
        "temporarily_unavailable",
        "overloaded",
        "rate_limit_exceeded",
        "timeout"
    ]

    let disposition: RealtimeErrorRetryDisposition
    if nonRetryableTypes.contains(type)
        || nonRetryableCodes.contains(code)
        || message.contains("invalid api key")
        || message.contains("incorrect api key")
        || message.contains("invalid model")
        || message.contains("unsupported voice")
        || message.contains("unsupported event")
        || message.contains("invalid value") {
        disposition = .nonRetryable
    } else if retryableTypes.contains(type)
        || retryableCodes.contains(code)
        || message.contains("please try again")
        || message.contains("temporarily")
        || message.contains("rate limit")
        || message.contains("server had an error")
        || message.contains("service unavailable") {
        disposition = .retryable
    } else {
        disposition = .retryable
    }

    return RealtimeErrorClassification(
        type: rawType,
        code: rawCode,
        message: rawMessage,
        param: param,
        eventId: eventId,
        disposition: disposition
    )
}

public struct RealtimeResponseDone: Decodable, Sendable {
    public let response: ResponseBody

    public struct ResponseBody: Decodable, Sendable {
        public let id: String?
        public let status: String?
        public let output: [OutputItem]?
    }

    public struct OutputItem: Decodable, Sendable {
        public let type: String?
        public let callId: String?
        public let name: String?
        public let arguments: String?

        enum CodingKeys: String, CodingKey {
            case type
            case callId = "call_id"
            case name
            case arguments
        }
    }

    public var functionCalls: [(callId: String, name: String, arguments: String)] {
        guard let output = response.output else {
            return []
        }

        return output.compactMap { item in
            guard item.type == "function_call",
                  let callId = item.callId,
                  let name = item.name,
                  let arguments = item.arguments else {
                return nil
            }

            return (callId: callId, name: name, arguments: arguments)
        }
    }
}

public struct RealtimeFunctionCallItem: Sendable {
    public let callId: String
    public let name: String
    public let arguments: String

    public init(callId: String, name: String, arguments: String) {
        self.callId = callId
        self.name = name
        self.arguments = arguments
    }
}

@MainActor
public protocol RealtimeClientDelegate: AnyObject {
    func realtimeClientDidConnect(_ client: any RealtimeClientProtocol)
    func realtimeClientDidBecomeReady(_ client: any RealtimeClientProtocol)
    func realtimeClientDidDisconnect(_ client: any RealtimeClientProtocol, error: Error?)
    func realtimeClient(_ client: any RealtimeClientProtocol, didChangeState state: RealtimeConnectionState)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveSessionCreated session: [String: Any])
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveSessionUpdated session: [String: Any])
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveError error: [String: Any])
    func realtimeClientDidDetectSpeechStarted(_ client: any RealtimeClientProtocol)
    func realtimeClientDidDetectSpeechStopped(_ client: any RealtimeClientProtocol)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveResponseCreated response: [String: Any])
    func realtimeClient(_ client: any RealtimeClientProtocol, didUpdateActiveAudioOutput itemId: String?, contentIndex: Int?)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioDelta base64Audio: String, itemId: String?, contentIndex: Int?)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioDone itemId: String, contentIndex: Int?)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioTranscriptDelta text: String)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioTranscriptDone text: String)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTextDelta text: String)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTextDone text: String)
    func realtimeClientDidReceiveResponseDone(_ client: any RealtimeClientProtocol)
    func realtimeClientDidReceiveResponseCancelled(_ client: any RealtimeClientProtocol)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTypedResponseDone response: RealtimeResponseDone)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveFunctionCallArgumentsDelta delta: String, callId: String)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveFunctionCallArgumentsDone arguments: String, callId: String)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveInputAudioTranscriptionDone text: String, itemId: String?)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveConversationItemCreated item: [String: Any])
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveConversationItemDone item: [String: Any])
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveFunctionCallItem call: RealtimeFunctionCallItem)
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveRateLimitsUpdated rateLimits: [[String: Any]])
}

public extension RealtimeClientDelegate {
    func realtimeClientDidConnect(_ client: any RealtimeClientProtocol) {}
    func realtimeClientDidBecomeReady(_ client: any RealtimeClientProtocol) {}
    func realtimeClientDidDisconnect(_ client: any RealtimeClientProtocol, error: Error?) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didChangeState state: RealtimeConnectionState) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveSessionCreated session: [String: Any]) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveSessionUpdated session: [String: Any]) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveError error: [String: Any]) {}
    func realtimeClientDidDetectSpeechStarted(_ client: any RealtimeClientProtocol) {}
    func realtimeClientDidDetectSpeechStopped(_ client: any RealtimeClientProtocol) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveResponseCreated response: [String: Any]) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didUpdateActiveAudioOutput itemId: String?, contentIndex: Int?) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioDelta base64Audio: String, itemId: String?, contentIndex: Int?) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioDone itemId: String, contentIndex: Int?) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioTranscriptDelta text: String) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioTranscriptDone text: String) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTextDelta text: String) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTextDone text: String) {}
    func realtimeClientDidReceiveResponseDone(_ client: any RealtimeClientProtocol) {}
    func realtimeClientDidReceiveResponseCancelled(_ client: any RealtimeClientProtocol) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTypedResponseDone response: RealtimeResponseDone) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveFunctionCallArgumentsDelta delta: String, callId: String) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveFunctionCallArgumentsDone arguments: String, callId: String) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveInputAudioTranscriptionDone text: String, itemId: String?) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveConversationItemCreated item: [String: Any]) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveConversationItemDone item: [String: Any]) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveFunctionCallItem call: RealtimeFunctionCallItem) {}
    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveRateLimitsUpdated rateLimits: [[String: Any]]) {}
}
