import Foundation
import AppKit

class TranscriptionManager: ObservableObject {

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
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            apiKey = nil
            logInfo("TranscriptionManager: Skipping keychain load in test environment")
            return
        }

        // Try Keychain first
        if let keychainKey = KeychainManager.loadAPIKey() {
            apiKey = keychainKey
            logInfo("TranscriptionManager: API key loaded from keychain")
            return
        }

        // Migrate from UserDefaults if present
        if let legacyKey = UserDefaults.standard.string(forKey: "OpenAIAPIKey"), !legacyKey.isEmpty {
            logInfo("Migrating API key from UserDefaults to Keychain")
            if KeychainManager.saveAPIKey(legacyKey) {
                apiKey = legacyKey
                UserDefaults.standard.removeObject(forKey: "OpenAIAPIKey")
                logInfo("TranscriptionManager: API key migration to keychain succeeded")
            } else {
                // Keep legacy key available for current session instead of dropping it.
                apiKey = legacyKey
                logError("TranscriptionManager: API key migration to keychain failed; legacy key retained in UserDefaults")
            }
            return
        }

        logInfo("TranscriptionManager: No API key configured")
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
