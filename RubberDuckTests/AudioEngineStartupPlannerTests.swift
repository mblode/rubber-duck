import XCTest
@testable import RubberDuck

final class AudioEngineStartupPlannerTests: XCTestCase {
    func test_makeStartupPlan_prefersVoiceProcessingThenFallsBackToStandard() {
        let plan = AudioEngineStartupPlanner.makeStartupPlan(
            preferVoiceProcessing: true,
            detectedInputChannels: 1,
            maxStartAttemptsPerMode: 3
        )

        XCTAssertEqual(
            plan,
            [
                AudioEngineStartupPlanStep(mode: .voiceProcessing, maxStartAttempts: 3),
                AudioEngineStartupPlanStep(mode: .standard, maxStartAttempts: 3)
            ]
        )
    }

    func test_makeStartupPlan_withoutVoiceProcessing_onlyUsesStandardMode() {
        let plan = AudioEngineStartupPlanner.makeStartupPlan(
            preferVoiceProcessing: false,
            detectedInputChannels: nil
        )
        XCTAssertEqual(plan, [AudioEngineStartupPlanStep(mode: .standard, maxStartAttempts: 2)])
    }

    func test_makeStartupPlan_withHighChannelInput_skipsVoiceProcessingMode() {
        let plan = AudioEngineStartupPlanner.makeStartupPlan(
            preferVoiceProcessing: true,
            detectedInputChannels: 9,
            maxStartAttemptsPerMode: 2
        )

        XCTAssertEqual(plan, [AudioEngineStartupPlanStep(mode: .standard, maxStartAttempts: 2)])
    }

    func test_shouldRetryEngineStart_onlyBeforeFinalAttempt_forRetryableErrors() {
        XCTAssertTrue(AudioEngineStartupPlanner.shouldRetryEngineStart(errorCode: nil, attempt: 1, maxAttempts: 2))
        XCTAssertFalse(AudioEngineStartupPlanner.shouldRetryEngineStart(errorCode: nil, attempt: 2, maxAttempts: 2))
        XCTAssertFalse(AudioEngineStartupPlanner.shouldRetryEngineStart(errorCode: nil, attempt: 1, maxAttempts: 1))
    }

    func test_shouldRetryEngineStart_treatsFailedInitializationAsRetryable() {
        XCTAssertTrue(AudioEngineStartupPlanner.shouldRetryEngineStart(errorCode: -10875, attempt: 1, maxAttempts: 2))
        XCTAssertFalse(AudioEngineStartupPlanner.shouldRetryEngineStart(errorCode: -10868, attempt: 1, maxAttempts: 2))
        XCTAssertFalse(AudioEngineStartupPlanner.shouldRetryEngineStart(errorCode: -66635, attempt: 1, maxAttempts: 2))
        XCTAssertTrue(AudioEngineStartupPlanner.shouldRetryEngineStart(errorCode: -50, attempt: 1, maxAttempts: 2))
    }

    func test_retryDelayNanoseconds_isExponentialAndCapped() {
        XCTAssertEqual(AudioEngineStartupPlanner.retryDelayNanoseconds(afterFailedAttempt: 1), 100_000_000)
        XCTAssertEqual(AudioEngineStartupPlanner.retryDelayNanoseconds(afterFailedAttempt: 2), 200_000_000)
        XCTAssertEqual(AudioEngineStartupPlanner.retryDelayNanoseconds(afterFailedAttempt: 3), 400_000_000)
        XCTAssertEqual(AudioEngineStartupPlanner.retryDelayNanoseconds(afterFailedAttempt: 6), 400_000_000)
    }
}
