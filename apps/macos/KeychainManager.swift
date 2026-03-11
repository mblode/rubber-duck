import Foundation
import Security

enum KeychainManager {
    private static let service = "co.blode.rubber-duck"
    private static let apiKeyAccount = "OpenAIAPIKey"

    @discardableResult
    static func saveAPIKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            logError("KeychainManager: Failed to clear existing API key before save (status: \(deleteStatus))")
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            logInfo("KeychainManager: API key saved to keychain")
            return true
        }

        logError("KeychainManager: Failed to save API key (status: \(status))")
        return false
    }

    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                logDebug("KeychainManager: No API key found in keychain")
            } else {
                logError("KeychainManager: Failed to load API key (status: \(status))")
            }
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            logInfo("KeychainManager: API key deleted from keychain")
            return true
        }
        if status == errSecItemNotFound {
            return true
        }
        logError("KeychainManager: Failed to delete API key (status: \(status))")
        return false
    }
}
