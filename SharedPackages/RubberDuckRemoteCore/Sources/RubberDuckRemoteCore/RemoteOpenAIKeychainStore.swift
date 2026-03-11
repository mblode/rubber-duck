import Foundation
import Security

public protocol RemoteOpenAIKeyStoring: Sendable {
    var hasAPIKey: Bool { get }

    func saveAPIKey(_ key: String) throws
    func loadAPIKey() -> String?
    func deleteAPIKey() throws
}

public enum RemoteOpenAIKeychainStoreError: LocalizedError, Sendable {
    case emptyAPIKey
    case encodingFailed
    case saveFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "Add an OpenAI API key to continue."
        case .encodingFailed:
            return "Failed to encode the OpenAI API key."
        case .saveFailed:
            return "Failed to save the OpenAI API key."
        case .deleteFailed:
            return "Failed to delete the OpenAI API key."
        }
    }
}

public struct RemoteOpenAIKeychainStore: Sendable, RemoteOpenAIKeyStoring {
    private let service: String
    private let account: String

    public var hasAPIKey: Bool {
        loadAPIKey() != nil
    }

    public init(
        service: String = "co.blode.rubber-duck.remote",
        account: String = "OpenAIAPIKey"
    ) {
        self.service = service
        self.account = account
    }

    public func saveAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw RemoteOpenAIKeychainStoreError.emptyAPIKey
        }
        guard let data = trimmedKey.data(using: .utf8) else {
            throw RemoteOpenAIKeychainStoreError.encodingFailed
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            logError("RemoteOpenAIKeychainStore: failed to clear existing API key (status: \(deleteStatus))")
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            logError("RemoteOpenAIKeychainStore: failed to save API key (status: \(status))")
            throw RemoteOpenAIKeychainStoreError.saveFailed(status: status)
        }

        logInfo("RemoteOpenAIKeychainStore: saved API key")
    }

    public func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else {
            if status != errSecItemNotFound {
                logError("RemoteOpenAIKeychainStore: failed to load API key (status: \(status))")
            }
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    public func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logError("RemoteOpenAIKeychainStore: failed to delete API key (status: \(status))")
            throw RemoteOpenAIKeychainStoreError.deleteFailed(status: status)
        }

        logInfo("RemoteOpenAIKeychainStore: deleted API key")
    }
}
