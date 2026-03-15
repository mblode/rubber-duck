import XCTest

private enum UITestEnvironmentKey {
    static let mode = "RUBBER_DUCK_UI_TEST_MODE"
    static let namespace = "RUBBER_DUCK_UI_TEST_NAMESPACE"
    static let resetState = "RUBBER_DUCK_UI_TEST_RESET_STATE"
    static let autoPair = "RUBBER_DUCK_UI_TEST_AUTO_PAIR"
    static let remoteURL = "RUBBER_DUCK_UI_TEST_REMOTE_URL"
    static let remoteToken = "RUBBER_DUCK_UI_TEST_REMOTE_TOKEN"
    static let hostName = "RUBBER_DUCK_UI_TEST_HOST_NAME"
    static let openAIKey = "RUBBER_DUCK_UI_TEST_OPENAI_KEY"
    static let prompt = "RUBBER_DUCK_UI_TEST_PROMPT"
    static let expectedSessionName = "RUBBER_DUCK_UI_TEST_EXPECTED_SESSION_NAME"
    static let expectedAssistantText = "RUBBER_DUCK_UI_TEST_EXPECTED_ASSISTANT_TEXT"
}

private enum UITestLaunchArgument {
    static let mode = "--uitesting"
    static let namespace = "--rubber-duck-ui-test-namespace"
    static let resetState = "--rubber-duck-ui-test-reset-state"
    static let autoPair = "--rubber-duck-ui-test-auto-pair"
    static let remoteURL = "--rubber-duck-ui-test-remote-url"
    static let remoteToken = "--rubber-duck-ui-test-remote-token"
    static let hostName = "--rubber-duck-ui-test-host-name"
    static let openAIKey = "--rubber-duck-ui-test-openai-key"
}

private enum UITestRemoteConfigDefaults {
    static let localhostConfigURL = URL(string: "http://127.0.0.1:43112/ios-ui-test-config.json")!
}

private func environmentValue(
    _ key: String,
    environment: [String: String]
) -> String? {
    if let value = environment[key], !value.isEmpty {
        return value
    }

    let simctlKey = "SIMCTL_CHILD_\(key)"
    if let value = environment[simctlKey], !value.isEmpty {
        return value
    }

    return nil
}

struct UITestRemoteConfiguration: Codable {
    let remoteURL: String
    let remoteToken: String
    let prompt: String
    let expectedHostName: String?
    let expectedSessionName: String?
    let expectedAssistantText: String?
    let openAIKey: String?

    static func fromEnvironment(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> UITestRemoteConfiguration {
        if let remoteURL = environmentValue(UITestEnvironmentKey.remoteURL, environment: environment),
           let remoteToken = environmentValue(UITestEnvironmentKey.remoteToken, environment: environment) {
            return UITestRemoteConfiguration(
                remoteURL: remoteURL,
                remoteToken: remoteToken,
                prompt: environmentValue(UITestEnvironmentKey.prompt, environment: environment) ?? "Summarize the daemon layout.",
                expectedHostName: environmentValue(UITestEnvironmentKey.hostName, environment: environment),
                expectedSessionName: environmentValue(UITestEnvironmentKey.expectedSessionName, environment: environment),
                expectedAssistantText: environmentValue(UITestEnvironmentKey.expectedAssistantText, environment: environment),
                openAIKey: environmentValue(UITestEnvironmentKey.openAIKey, environment: environment)
            )
        }

        if let configuration = try loadFromLocalhost() {
            return configuration
        }

        throw XCTSkip("Set \(UITestEnvironmentKey.remoteURL) or start the localhost UI-test config server to run the live typed-prompt UI test.")
    }

    private static func loadFromLocalhost() throws -> UITestRemoteConfiguration? {
        var request = URLRequest(url: UITestRemoteConfigDefaults.localhostConfigURL)
        request.timeoutInterval = 2

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?

        URLSession.shared.dataTask(with: request) { data, _, error in
            responseData = data
            responseError = error
            semaphore.signal()
        }.resume()

        let waitResult = semaphore.wait(timeout: .now() + 3)
        guard waitResult == .success else {
            return nil
        }

        if let nsError = responseError as NSError?,
           nsError.domain == NSURLErrorDomain {
            return nil
        }

        guard let responseData else {
            return nil
        }

        return try JSONDecoder().decode(UITestRemoteConfiguration.self, from: responseData)
    }
}

enum UITestApp {
    @discardableResult
    static func launch(
        remoteConfiguration: UITestRemoteConfiguration? = nil,
        autoPair: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let namespace = UUID().uuidString

        app.launchArguments = [
            UITestLaunchArgument.mode,
            UITestLaunchArgument.namespace,
            namespace,
            UITestLaunchArgument.resetState
        ]
        app.launchEnvironment[UITestEnvironmentKey.mode] = "1"
        app.launchEnvironment[UITestEnvironmentKey.namespace] = namespace
        app.launchEnvironment[UITestEnvironmentKey.resetState] = "1"

        if let remoteConfiguration {
            app.launchArguments.append(contentsOf: [
                UITestLaunchArgument.remoteURL,
                remoteConfiguration.remoteURL,
                UITestLaunchArgument.remoteToken,
                remoteConfiguration.remoteToken,
            ])
            app.launchEnvironment[UITestEnvironmentKey.remoteURL] = remoteConfiguration.remoteURL
            app.launchEnvironment[UITestEnvironmentKey.remoteToken] = remoteConfiguration.remoteToken
            app.launchEnvironment[UITestEnvironmentKey.prompt] = remoteConfiguration.prompt

            if autoPair {
                app.launchArguments.append(UITestLaunchArgument.autoPair)
                app.launchEnvironment[UITestEnvironmentKey.autoPair] = "1"
            }

            if let expectedHostName = remoteConfiguration.expectedHostName {
                app.launchArguments.append(contentsOf: [
                    UITestLaunchArgument.hostName,
                    expectedHostName,
                ])
                app.launchEnvironment[UITestEnvironmentKey.hostName] = expectedHostName
            }

            if let openAIKey = remoteConfiguration.openAIKey {
                app.launchArguments.append(contentsOf: [
                    UITestLaunchArgument.openAIKey,
                    openAIKey,
                ])
                app.launchEnvironment[UITestEnvironmentKey.openAIKey] = openAIKey
            }
        }

        app.launch()
        return app
    }
}

extension XCUIApplication {
    var composerPromptField: XCUIElement {
        let textField = textFields["Send a prompt..."]
        if textField.exists {
            return textField
        }

        let textView = textViews["Send a prompt..."]
        if textView.exists {
            return textView
        }

        let anyTextField = textFields.firstMatch
        if anyTextField.exists {
            return anyTextField
        }

        return textViews.firstMatch
    }

    var composerSendButton: XCUIElement {
        let explicitCandidates = [
            buttons["composer-send-button"],
            buttons["voice-send-button"],
            buttons["Send Prompt"],
            buttons["Send"],
            buttons["paperplane.fill"],
            buttons["arrow.up.circle.fill"],
        ]

        if let match = explicitCandidates.first(where: \.exists) {
            return match
        }

        let hittableButtons = buttons.allElementsBoundByIndex.filter(\.isHittable)
        if let fallback = hittableButtons.last {
            return fallback
        }

        return buttons.firstMatch
    }
}
