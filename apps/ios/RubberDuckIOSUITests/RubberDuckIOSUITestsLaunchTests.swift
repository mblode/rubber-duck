import XCTest

final class RubberDuckIOSUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsPrimaryEmptyState() throws {
        let app = UITestApp.launch()

        XCTAssertTrue(app.staticTexts["Rubber Duck Remote"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Unpaired Empty State"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
