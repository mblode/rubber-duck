import Foundation
import Security

public enum RemoteCredentialStoreError: Error, LocalizedError, Equatable, Sendable {
    case invalidToken
    case missingToken
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Enter the remote access token from your Mac."
        case .missingToken:
            return "This paired Mac is missing its remote access token. Pair it again to continue."
        case .saveFailed:
            return "Couldn't save the credential securely on this device."
        case .loadFailed:
            return "Couldn't load the stored credential."
        case .deleteFailed:
            return "Couldn't remove the stored credential."
        }
    }
}

public struct RemoteCredentialStore: Sendable {
    private let service: String

    public init(service: String = "co.blode.rubber-duck.remote-daemon") {
        self.service = service
    }

    public func saveToken(_ token: String, for hostID: String) throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty,
              let data = normalizedToken.data(using: .utf8) else {
            throw RemoteCredentialStoreError.invalidToken
        }

        let baseQuery = credentialQuery(for: hostID)
        let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            throw RemoteCredentialStoreError.deleteFailed(deleteStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw RemoteCredentialStoreError.saveFailed(status)
        }
    }

    public func loadToken(for hostID: String) throws -> String {
        var query = credentialQuery(for: hostID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            throw RemoteCredentialStoreError.missingToken
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw RemoteCredentialStoreError.loadFailed(status)
        }

        guard let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw RemoteCredentialStoreError.invalidToken
        }

        return token
    }

    public func deleteToken(for hostID: String) throws {
        let status = SecItemDelete(credentialQuery(for: hostID) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw RemoteCredentialStoreError.deleteFailed(status)
        }
    }

    private func credentialQuery(for hostID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID,
        ]
    }
}
