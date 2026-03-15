import XCTest

final class RubberDuckIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsUnpairedEmptyState() throws {
        let app = UITestApp.launch()

        XCTAssertTrue(app.staticTexts["Rubber Duck Remote"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["empty-state-action-button"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Pair this phone with your Mac to start voice coding against a live repo."].exists)
    }

    @MainActor
    func testPairingSheetAcceptsManualEntry() throws {
        let app = UITestApp.launch()

        let pairButton = app.buttons["empty-state-action-button"]
        XCTAssertTrue(pairButton.waitForExistence(timeout: 2))
        pairButton.tap()

        XCTAssertTrue(app.navigationBars["Pair a Mac"].waitForExistence(timeout: 2))

        let displayNameField = app.textFields["pairing-display-name-field"]
        XCTAssertTrue(displayNameField.waitForExistence(timeout: 2))
        displayNameField.tap()
        displayNameField.typeText("UI Test Mac")
        XCTAssertEqual(displayNameField.value as? String, "UI Test Mac")

        let hostField = app.textFields["pairing-host-field"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 2))
        hostField.tap()
        hostField.typeText("http://localhost:43111")
        XCTAssertEqual(hostField.value as? String, "http://localhost:43111")

        let secureTokenField = app.secureTextFields["pairing-token-field"]
        let tokenField = secureTokenField.waitForExistence(timeout: 2)
            ? secureTokenField
            : app.textFields["pairing-token-field"]
        XCTAssertTrue(tokenField.waitForExistence(timeout: 2))
        tokenField.tap()
        tokenField.typeText("duck-ui-test-token")

        XCTAssertTrue(app.buttons["pairing-save-button"].exists)
    }

    @MainActor
    func testTypedPromptRemoteControlFlow() throws {
        let remoteConfiguration = try UITestRemoteConfiguration.fromEnvironment()
        let app = UITestApp.launch(remoteConfiguration: remoteConfiguration)

        let pairButton = app.buttons["empty-state-action-button"]
        XCTAssertTrue(pairButton.waitForExistence(timeout: 5))
        pairButton.tap()

        XCTAssertTrue(app.navigationBars["Pair a Mac"].waitForExistence(timeout: 2))

        let displayNameField = app.textFields["pairing-display-name-field"]
        XCTAssertTrue(displayNameField.waitForExistence(timeout: 2))
        if let expectedHostName = remoteConfiguration.expectedHostName {
            XCTAssertEqual(displayNameField.value as? String, expectedHostName)
        }

        let hostField = app.textFields["pairing-host-field"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 2))
        XCTAssertEqual(hostField.value as? String, remoteConfiguration.remoteURL)

        let secureTokenField = app.secureTextFields["pairing-token-field"]
        let tokenField = secureTokenField.waitForExistence(timeout: 2)
            ? secureTokenField
            : app.textFields["pairing-token-field"]
        XCTAssertTrue(tokenField.waitForExistence(timeout: 2))
        XCTAssertNotEqual(tokenField.value as? String, "")

        let saveButton = app.buttons["pairing-save-button"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        saveButton.tap()

        let tabBar = app.tabBars.firstMatch
        if !tabBar.waitForExistence(timeout: 15) {
            let alertTexts = app.alerts.staticTexts.allElementsBoundByIndex
                .map(\.label)
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
            let visibleLabels = (
                app.staticTexts.allElementsBoundByIndex.map(\.label) +
                app.buttons.allElementsBoundByIndex.map(\.label) +
                app.navigationBars.allElementsBoundByIndex.map(\.label)
            )
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
            XCTFail("App never reached paired state after manual pairing. Alerts: \(alertTexts). Visible UI: \(visibleLabels)")
        }
        XCTAssertTrue(app.buttons["Voice"].exists)
        XCTAssertTrue(app.buttons["Sessions"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists)

        if let expectedHostName = remoteConfiguration.expectedHostName {
            XCTAssertTrue(app.staticTexts[expectedHostName].waitForExistence(timeout: 10))
        }
        if let expectedSessionName = remoteConfiguration.expectedSessionName {
            XCTAssertTrue(
                app.staticTexts[expectedSessionName].waitForExistence(timeout: 10),
                "Expected active session \(expectedSessionName) was not visible after pairing. Alerts: \(alertSummary(in: app)). Visible UI: \(visibleSummary(in: app))"
            )
        }

        dismissAlertIfNeeded(in: app)

        let promptField = app.composerPromptField
        XCTAssertTrue(
            promptField.waitForExistence(timeout: 10),
            "Prompt composer never became available. Alerts: \(alertSummary(in: app)). Visible UI: \(visibleSummary(in: app))"
        )
        promptField.tap()
        promptField.typeText(remoteConfiguration.prompt)

        let sendButton = app.composerSendButton
        XCTAssertTrue(sendButton.waitForExistence(timeout: 2))
        sendButton.tap()

        XCTAssertTrue(app.staticTexts[remoteConfiguration.prompt].waitForExistence(timeout: 15))

        if let expectedAssistantText = remoteConfiguration.expectedAssistantText {
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", expectedAssistantText)).firstMatch.waitForExistence(timeout: 20))
        }
    }

    private func dismissAlertIfNeeded(in app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 1) else {
            return
        }

        let buttons = alert.buttons.allElementsBoundByIndex
        guard let button = buttons.first(where: \.isHittable) ?? buttons.first else {
            return
        }

        button.tap()
    }

    private func alertSummary(in app: XCUIApplication) -> String {
        let labels = app.alerts.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty }
        return labels.isEmpty ? "none" : labels.joined(separator: " | ")
    }

    private func visibleSummary(in app: XCUIApplication) -> String {
        let labels = (
            app.staticTexts.allElementsBoundByIndex.map(\.label) +
            app.buttons.allElementsBoundByIndex.map(\.label) +
            app.navigationBars.allElementsBoundByIndex.map(\.label)
        )
        .filter { !$0.isEmpty }
        return labels.isEmpty ? "none" : labels.joined(separator: " | ")
    }
}
