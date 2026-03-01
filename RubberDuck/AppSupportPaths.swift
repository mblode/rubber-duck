import Foundation
import CryptoKit

enum AppSupportPaths {
    static let appSupportOverrideEnv = "RUBBER_DUCK_APP_SUPPORT"
    private static let unixSocketPathMax = 104

    private static let standardRelativePath = "Library/Application Support/RubberDuck"
    private static let legacyContainerRelativePath =
        "Library/Containers/co.blode.rubber-duck/Data/Library/Application Support/RubberDuck"

    static func rootURL(
        fileManager: FileManager = .default,
        processInfo: ProcessInfo = .processInfo
    ) -> URL {
        let override = processInfo.environment[appSupportOverrideEnv]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let standardRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(standardRelativePath, isDirectory: true)
        let legacyContainerRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(legacyContainerRelativePath, isDirectory: true)

        return resolveRootURL(
            override: override,
            standardRoot: standardRoot,
            legacyContainerRoot: legacyContainerRoot,
            fileExists: { fileManager.fileExists(atPath: $0) }
        )
    }

    static func resolveRootURL(
        override: String?,
        standardRoot: URL,
        legacyContainerRoot: URL,
        fileExists: (String) -> Bool
    ) -> URL {
        if let override {
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return URL(fileURLWithPath: trimmed, isDirectory: true)
            }
        }

        if fileExists(standardRoot.path) {
            return standardRoot
        }

        if fileExists(legacyContainerRoot.path) {
            return legacyContainerRoot
        }

        return standardRoot
    }

    static func metadataFileURL(
        fileManager: FileManager = .default,
        processInfo: ProcessInfo = .processInfo
    ) -> URL {
        rootURL(fileManager: fileManager, processInfo: processInfo)
            .appendingPathComponent("metadata.json")
    }

    static func sessionsDirectoryURL(
        fileManager: FileManager = .default,
        processInfo: ProcessInfo = .processInfo
    ) -> URL {
        rootURL(fileManager: fileManager, processInfo: processInfo)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    static func logFileURL(
        fileManager: FileManager = .default,
        processInfo: ProcessInfo = .processInfo
    ) -> URL {
        rootURL(fileManager: fileManager, processInfo: processInfo)
            .appendingPathComponent("RubberDuck.log")
    }

    static func daemonSocketURL(
        fileManager: FileManager = .default,
        processInfo: ProcessInfo = .processInfo
    ) -> URL {
        let root = rootURL(fileManager: fileManager, processInfo: processInfo)
        let preferred = root
            .appendingPathComponent("daemon.sock")
            .path
        if preferred.count < unixSocketPathMax {
            return URL(fileURLWithPath: preferred, isDirectory: false)
        }

        let digest = SHA256.hash(data: Data(root.path.utf8))
        let suffix = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        let fallbackPath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rubber-duck-\(suffix).sock", isDirectory: false)
            .path
        return URL(fileURLWithPath: fallbackPath, isDirectory: false)
    }

    static func isRunningTests(processInfo: ProcessInfo = .processInfo) -> Bool {
        let env = processInfo.environment
        return AppEnvironment.isRunningTests ||
            env["XCTestBundlePath"] != nil ||
            env["XCTestSessionIdentifier"] != nil
    }
}
