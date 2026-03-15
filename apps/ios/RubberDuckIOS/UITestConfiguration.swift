import Foundation
import RubberDuckRemoteCore

private let defaultDirectRemotePort = 43_111

private enum UITestEnvironmentKey {
    static let mode = "RUBBER_DUCK_UI_TEST_MODE"
    static let namespace = "RUBBER_DUCK_UI_TEST_NAMESPACE"
    static let resetState = "RUBBER_DUCK_UI_TEST_RESET_STATE"
    static let autoPair = "RUBBER_DUCK_UI_TEST_AUTO_PAIR"
    static let remoteURL = "RUBBER_DUCK_UI_TEST_REMOTE_URL"
    static let remoteToken = "RUBBER_DUCK_UI_TEST_REMOTE_TOKEN"
    static let hostName = "RUBBER_DUCK_UI_TEST_HOST_NAME"
    static let openAIKey = "RUBBER_DUCK_UI_TEST_OPENAI_KEY"
    static let mockTransport = "RUBBER_DUCK_UI_TEST_USE_MOCK_TRANSPORT"
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
    static let mockTransport = "--rubber-duck-ui-test-use-mock-transport"
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

private func hasArgument(_ flag: String, arguments: [String]) -> Bool {
    arguments.contains(flag)
}

private func argumentValue(_ flag: String, arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag),
          arguments.indices.contains(index + 1) else {
        return nil
    }

    return arguments[index + 1]
}

struct UITestPairingSeed: Sendable {
    let hostURLString: String
    let displayName: String
    let authToken: String
}

struct AppRuntimeConfiguration: Sendable {
    let isUITestMode: Bool
    let resetStateOnLaunch: Bool
    let autoPairOnLaunch: Bool
    let pairingSeed: UITestPairingSeed?
    let openAIKey: String?
    let usesMockTransport: Bool

    private let pairingStoreURLValue: URL?
    private let remoteCredentialStoreURLValue: URL?
    private let remoteCredentialServiceValue: String?
    private let openAIServiceValue: String?
    private let openAIAccountValue: String?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        let uiTestMode = environmentValue(UITestEnvironmentKey.mode, environment: environment) == "1"
            || hasArgument(UITestLaunchArgument.mode, arguments: arguments)
        let namespace = AppRuntimeConfiguration.trimmed(
            argumentValue(UITestLaunchArgument.namespace, arguments: arguments)
            ?? environmentValue(UITestEnvironmentKey.namespace, environment: environment)
        ) ?? "default"
        let remoteURL = AppRuntimeConfiguration.trimmed(
            argumentValue(UITestLaunchArgument.remoteURL, arguments: arguments)
            ?? environmentValue(UITestEnvironmentKey.remoteURL, environment: environment)
        )
        let remoteToken = AppRuntimeConfiguration.trimmed(
            argumentValue(UITestLaunchArgument.remoteToken, arguments: arguments)
            ?? environmentValue(UITestEnvironmentKey.remoteToken, environment: environment)
        )
        let hostName = AppRuntimeConfiguration.trimmed(
            argumentValue(UITestLaunchArgument.hostName, arguments: arguments)
            ?? environmentValue(UITestEnvironmentKey.hostName, environment: environment)
        ) ?? "UI Test Mac"
        let openAIKey = AppRuntimeConfiguration.trimmed(
            argumentValue(UITestLaunchArgument.openAIKey, arguments: arguments)
            ?? environmentValue(UITestEnvironmentKey.openAIKey, environment: environment)
        )

        isUITestMode = uiTestMode
        resetStateOnLaunch = uiTestMode
            && (
                hasArgument(UITestLaunchArgument.resetState, arguments: arguments)
                || environmentValue(UITestEnvironmentKey.resetState, environment: environment) == "1"
            )
        autoPairOnLaunch = uiTestMode
            && (
                hasArgument(UITestLaunchArgument.autoPair, arguments: arguments)
                || environmentValue(UITestEnvironmentKey.autoPair, environment: environment) == "1"
            )
            && remoteURL != nil
            && remoteToken != nil
        usesMockTransport = uiTestMode
            && (
                hasArgument(UITestLaunchArgument.mockTransport, arguments: arguments)
                || environmentValue(UITestEnvironmentKey.mockTransport, environment: environment) == "1"
            )
        self.openAIKey = openAIKey

        if let remoteURL, let remoteToken {
            pairingSeed = UITestPairingSeed(
                hostURLString: remoteURL,
                displayName: hostName,
                authToken: remoteToken
            )
        } else {
            pairingSeed = nil
        }

        if uiTestMode {
            let supportDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("RubberDuckIOS-UITests", isDirectory: true)
            pairingStoreURLValue = supportDirectory
                .appendingPathComponent("\(namespace)-remote-pairings.json", isDirectory: false)
            remoteCredentialStoreURLValue = supportDirectory
                .appendingPathComponent("\(namespace)-remote-credentials.json", isDirectory: false)
            remoteCredentialServiceValue = "co.blode.rubber-duck.remote-daemon.\(namespace)"
            openAIServiceValue = "co.blode.rubber-duck.remote.\(namespace)"
            openAIAccountValue = "OpenAIAPIKey.\(namespace)"
        } else {
            pairingStoreURLValue = nil
            remoteCredentialStoreURLValue = nil
            remoteCredentialServiceValue = nil
            openAIServiceValue = nil
            openAIAccountValue = nil
        }
    }

    var pairingStoreURL: URL? {
        pairingStoreURLValue
    }

    func makePairingStore() -> RemotePairingStore {
        RemotePairingStore(fileURL: pairingStoreURLValue)
    }

    func makeRemoteCredentialStore() -> RemoteCredentialStore {
        if let remoteCredentialStoreURLValue {
            return RemoteCredentialStore(fileURL: remoteCredentialStoreURLValue)
        }

        if let remoteCredentialServiceValue {
            return RemoteCredentialStore(service: remoteCredentialServiceValue)
        }
        return RemoteCredentialStore()
    }

    func makeOpenAIKeyStore() -> RemoteOpenAIKeychainStore {
        if let openAIServiceValue, let openAIAccountValue {
            return RemoteOpenAIKeychainStore(
                service: openAIServiceValue,
                account: openAIAccountValue
            )
        }
        return RemoteOpenAIKeychainStore()
    }

    func makeTransport() -> any RemoteDaemonTransport {
        if usesMockTransport {
            return MockRemoteDaemonTransport()
        }

        return RemoteDaemonHTTPTransport(
            credentialStore: makeRemoteCredentialStore()
        )
    }

    func makeVoiceModel() -> RemoteIOSVoiceSessionModel {
        let credentialStore = makeRemoteCredentialStore()
        return RemoteIOSVoiceSessionModel(
            daemonChannel: RemoteVoiceDaemonChannel(credentialStore: credentialStore),
            credentialStore: makeOpenAIKeyStore()
        )
    }

    func seedLaunchStateIfNeeded() {
        guard autoPairOnLaunch,
              let pairingSeed,
              let hostURL = Self.normalizedHostURL(from: pairingSeed.hostURLString) else {
            return
        }

        let normalizedToken = pairingSeed.authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            return
        }

        let displayName = pairingSeed.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (hostURL.host ?? "Rubber Duck Mac")
            : pairingSeed.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = PairedRemoteHost(
            id: hostURL.absoluteString.lowercased(),
            displayName: displayName,
            baseURL: hostURL,
            authToken: "",
            pairingCodeHint: String(normalizedToken.suffix(4)).uppercased()
        )

        do {
            try makeRemoteCredentialStore().saveToken(normalizedToken, for: host.id)

            var snapshot = makePairingStore().load()
            snapshot.hosts.removeAll(where: { $0.id == host.id })
            snapshot.hosts.insert(host, at: 0)
            snapshot.selectedHostID = host.id
            try makePairingStore().save(snapshot)
        } catch {
            return
        }
    }

    func resetPersistedState() {
        let pairingStore = makePairingStore()
        let credentialStore = makeRemoteCredentialStore()
        let snapshot = pairingStore.load()

        for host in snapshot.hosts {
            try? credentialStore.deleteToken(for: host.id)
        }

        if let pairingStoreURLValue {
            try? FileManager.default.removeItem(at: pairingStoreURLValue)
        }

        if let remoteCredentialStoreURLValue {
            try? FileManager.default.removeItem(at: remoteCredentialStoreURLValue)
        }

        try? makeOpenAIKeyStore().deleteAPIKey()
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedHostURL(from rawValue: String) -> URL? {
        let trimmedValue = trimmed(rawValue)
        guard let trimmedValue else {
            return nil
        }

        if let url = URL(string: trimmedValue),
           let scheme = url.scheme,
           !scheme.isEmpty {
            return normalizedHostURL(url)
        }

        let inferredScheme = trimmedValue.lowercased().contains(".ts.net")
            ? "https"
            : "http"

        guard let url = URL(string: "\(inferredScheme)://\(trimmedValue)") else {
            return nil
        }

        return normalizedHostURL(url)
    }

    private static func normalizedHostURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawScheme = components.scheme?.lowercased(),
              let host = components.host,
              rawScheme == "http" || rawScheme == "https" else {
            return nil
        }

        components.scheme = rawScheme
        components.host = host
        components.path = ""
        components.query = nil
        components.fragment = nil

        if rawScheme == "http" && components.port == nil {
            components.port = defaultDirectRemotePort
        }

        return components.url
    }
}
