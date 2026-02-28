import XCTest
@testable import RubberDuck

final class RealtimeClientErrorHandlingTests: XCTestCase {

    func test_classify_serverError_isRetryable() {
        let payload: [String: Any] = [
            "type": "server_error",
            "code": "internal_server_error",
            "message": "The server had an error while processing your request. Please try again."
        ]

        let result = classifyRealtimeErrorPayload(payload)

        XCTAssertEqual(result.disposition, .retryable)
    }

    func test_classify_invalidRequest_isNonRetryable() {
        let payload: [String: Any] = [
            "type": "invalid_request_error",
            "code": "invalid_value",
            "message": "Invalid value for model"
        ]

        let result = classifyRealtimeErrorPayload(payload)

        XCTAssertEqual(result.disposition, .nonRetryable)
    }

    func test_classify_invalidModelCode_isNonRetryable() {
        let payload: [String: Any] = [
            "type": "error",
            "code": "invalid_model",
            "message": "Model not found"
        ]

        let result = classifyRealtimeErrorPayload(payload)

        XCTAssertEqual(result.disposition, .nonRetryable)
    }

    func test_shouldReconnect_retryableWithinBudget_returnsTrue() {
        XCTAssertTrue(
            RealtimeReconnectionPolicy.shouldReconnect(
                intentionalDisconnect: false,
                disposition: .retryable,
                reconnectAttempt: 1,
                maxReconnectAttempts: 3
            )
        )
    }

    func test_shouldReconnect_nonRetryable_returnsFalse() {
        XCTAssertFalse(
            RealtimeReconnectionPolicy.shouldReconnect(
                intentionalDisconnect: false,
                disposition: .nonRetryable,
                reconnectAttempt: 0,
                maxReconnectAttempts: 3
            )
        )
    }

    func test_shouldReconnect_attemptsExhausted_returnsFalse() {
        XCTAssertFalse(
            RealtimeReconnectionPolicy.shouldReconnect(
                intentionalDisconnect: false,
                disposition: .retryable,
                reconnectAttempt: 3,
                maxReconnectAttempts: 3
            )
        )
    }

    func test_shouldUseMinimalStartupConfigFallback_initialAttempt_returnsFalse() {
        XCTAssertFalse(RealtimeReconnectionPolicy.shouldUseMinimalStartupConfigFallback(reconnectAttempt: 0))
    }

    func test_shouldUseMinimalStartupConfigFallback_retryAttempt_returnsTrue() {
        XCTAssertTrue(RealtimeReconnectionPolicy.shouldUseMinimalStartupConfigFallback(reconnectAttempt: 1))
    }

    func test_resolvedModelForConnectionAttempt_beforeSecondRetry_usesConfiguredModel() {
        XCTAssertEqual(
            RealtimeReconnectionPolicy.resolvedModelForConnectionAttempt(
                configuredModel: "gpt-realtime-1.5",
                reconnectAttempt: 1
            ),
            "gpt-realtime-1.5"
        )
    }

    func test_resolvedModelForConnectionAttempt_secondRetry_fallsBackToMini() {
        XCTAssertEqual(
            RealtimeReconnectionPolicy.resolvedModelForConnectionAttempt(
                configuredModel: "gpt-realtime-1.5",
                reconnectAttempt: 2
            ),
            "gpt-realtime-mini"
        )
    }

    func test_resolvedModelForConnectionAttempt_customModel_notOverridden() {
        XCTAssertEqual(
            RealtimeReconnectionPolicy.resolvedModelForConnectionAttempt(
                configuredModel: "gpt-4o-realtime-preview",
                reconnectAttempt: 3
            ),
            "gpt-4o-realtime-preview"
        )
    }

    func test_regression_sessionCreatedThenServerError_canRecoverViaReconnectPolicy() {
        let payload: [String: Any] = [
            "type": "server_error",
            "code": "internal_server_error",
            "message": "The server had an error while processing your request. We recommend you retry your request."
        ]

        let result = classifyRealtimeErrorPayload(payload)
        let shouldReconnect = RealtimeReconnectionPolicy.shouldReconnect(
            intentionalDisconnect: false,
            disposition: result.disposition,
            reconnectAttempt: 0,
            maxReconnectAttempts: 3
        )

        XCTAssertEqual(result.disposition, .retryable)
        XCTAssertTrue(shouldReconnect)
    }
}
