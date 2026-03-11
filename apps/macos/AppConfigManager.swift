import Foundation

class AppConfigManager: ObservableObject {

    @Published var statusMessage = ""
    @Published var setupGuideDismissed: Bool = UserDefaults.standard.bool(forKey: "setupGuideDismissed") {
        didSet { UserDefaults.standard.set(setupGuideDismissed, forKey: "setupGuideDismissed") }
    }
    private var apiKey: String?

    init() {
        loadAPIKey()
    }

    // MARK: - API Key (Keychain)

    private func loadAPIKey() {
        // XCTest host startup can block indefinitely on keychain IPC.
        if AppEnvironment.isRunningTests {
            apiKey = nil
            logInfo("AppConfigManager: Skipping keychain load in test environment")
            return
        }

        // Try Keychain first
        if let keychainKey = KeychainManager.loadAPIKey() {
            apiKey = keychainKey
            logInfo("AppConfigManager: API key loaded from keychain")
            return
        }

        logInfo("AppConfigManager: No API key configured")
    }

    @discardableResult
    func setAPIKey(_ key: String) -> Bool {
        if key.isEmpty {
            let didDelete = KeychainManager.deleteAPIKey()
            if didDelete {
                apiKey = nil
            }
            return didDelete
        } else {
            let didSave = KeychainManager.saveAPIKey(key)
            if didSave {
                apiKey = key
            }
            return didSave
        }
    }

    func getAPIKey() -> String? {
        return apiKey
    }

    func resetSetupGuide() {
        setupGuideDismissed = false
    }

    func setStatusMessage(_ message: String) {
        DispatchQueue.main.async { self.statusMessage = message }
    }
}
