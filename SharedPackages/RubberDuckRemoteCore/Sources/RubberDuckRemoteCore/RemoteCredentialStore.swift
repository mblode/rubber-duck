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
    private enum Backend: Sendable {
        case keychain(service: String)
        case file(URL)
    }

    private struct FilePayload: Codable, Sendable {
        var tokens: [String: String]
    }

    private let backend: Backend

    public init(service: String = "co.blode.rubber-duck.remote-daemon") {
        backend = .keychain(service: service)
    }

    public init(fileURL: URL) {
        backend = .file(fileURL)
    }

    public func saveToken(_ token: String, for hostID: String) throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty,
              let data = normalizedToken.data(using: .utf8) else {
            throw RemoteCredentialStoreError.invalidToken
        }

        switch backend {
        case .keychain(let service):
            let baseQuery = credentialQuery(for: hostID, service: service)
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

        case .file(let fileURL):
            var payload = try loadFilePayload(from: fileURL)
            payload.tokens[hostID] = normalizedToken
            try saveFilePayload(payload, to: fileURL)
        }
    }

    public func loadToken(for hostID: String) throws -> String {
        switch backend {
        case .keychain(let service):
            var query = credentialQuery(for: hostID, service: service)
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

        case .file(let fileURL):
            let payload = try loadFilePayload(from: fileURL)
            guard let token = payload.tokens[hostID] else {
                throw RemoteCredentialStoreError.missingToken
            }
            return token
        }
    }

    public func deleteToken(for hostID: String) throws {
        switch backend {
        case .keychain(let service):
            let status = SecItemDelete(credentialQuery(for: hostID, service: service) as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                throw RemoteCredentialStoreError.deleteFailed(status)
            }

        case .file(let fileURL):
            var payload = try loadFilePayload(from: fileURL)
            payload.tokens.removeValue(forKey: hostID)

            if payload.tokens.isEmpty {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
            } else {
                try saveFilePayload(payload, to: fileURL)
            }
        }
    }

    private func credentialQuery(for hostID: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID,
        ]
    }

    private func loadFilePayload(from fileURL: URL) throws -> FilePayload {
        guard let data = try? Data(contentsOf: fileURL) else {
            return FilePayload(tokens: [:])
        }

        return try JSONDecoder().decode(FilePayload.self, from: data)
    }

    private func saveFilePayload(_ payload: FilePayload, to fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: .atomic)
    }
}
