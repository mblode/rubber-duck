import XCTest
@testable import RubberDuck

final class OverlayStateTests: XCTestCase {

    func test_equatable_sameCase() {
        XCTAssertEqual(OverlayState.listening, OverlayState.listening)
        XCTAssertEqual(OverlayState.thinking, OverlayState.thinking)
        XCTAssertEqual(OverlayState.speaking, OverlayState.speaking)
        XCTAssertEqual(OverlayState.toolRunning("grep"), OverlayState.toolRunning("grep"))
        XCTAssertEqual(OverlayState.error("oops"), OverlayState.error("oops"))
    }

    func test_equatable_differentCases() {
        XCTAssertNotEqual(OverlayState.listening, OverlayState.thinking)
        XCTAssertNotEqual(OverlayState.thinking, OverlayState.speaking)
        XCTAssertNotEqual(OverlayState.speaking, OverlayState.listening)
        XCTAssertNotEqual(OverlayState.toolRunning("a"), OverlayState.toolRunning("b"))
        XCTAssertNotEqual(OverlayState.error("a"), OverlayState.error("b"))
        XCTAssertNotEqual(OverlayState.toolRunning("x"), OverlayState.listening)
    }

    func test_allCasesDistinct() {
        let states: [OverlayState] = [.listening, .thinking, .speaking, .toolRunning("test"), .error("test")]
        let unique = Set(states.map { "\($0)" })
        XCTAssertEqual(unique.count, 5)
    }
}
