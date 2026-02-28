import Foundation
import AppKit

class Logger {
    static let shared = Logger()

    private static let logPathOverrideEnv = "RUBBER_DUCK_LOG_PATH"
    private static let logLevelEnv = "RUBBER_DUCK_LOG_LEVEL"
    private static let disableFileLoggingEnv = "RUBBER_DUCK_DISABLE_FILE_LOGGING"
    private static let logToStderrEnv = "RUBBER_DUCK_LOG_STDERR"

    private let logQueue = DispatchQueue(label: "co.blode.rubber-duck.logger")
    private let fileManager: FileManager
    private let logFileURL: URL?
    private let dateFormatter: DateFormatter
    private let minimumLevel: LogLevel
    private let logToStderr: Bool

    enum LogLevel: String {
        case info = "INFO"
        case error = "ERROR"
        case debug = "DEBUG"

        var priority: Int {
            switch self {
            case .debug:
                return 0
            case .info:
                return 1
            case .error:
                return 2
            }
        }
    }

    private init(fileManager: FileManager = .default, processInfo: ProcessInfo = .processInfo) {
        self.fileManager = fileManager
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.minimumLevel = Self.resolveMinimumLevel(processInfo: processInfo)
        self.logToStderr = Self.parseBool(processInfo.environment[Self.logToStderrEnv]) ?? false
        self.logFileURL = Self.resolveLogFileURL(fileManager: fileManager, processInfo: processInfo)
        log("RubberDuck application launched", level: .info)
    }

    func log(_ message: String, level: LogLevel = .info) {
        guard level.priority >= minimumLevel.priority else {
            return
        }

        logQueue.sync {
            let timestamp = dateFormatter.string(from: Date())
            let logMessage = "[\(timestamp)] [\(level.rawValue)] \(message)\n"

            if logToStderr {
                fputs(logMessage, stderr)
            }

            guard let logFileURL else {
                return
            }

            do {
                try fileManager.createDirectory(
                    at: logFileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                if fileManager.fileExists(atPath: logFileURL.path) {
                    let fileHandle = try FileHandle(forWritingTo: logFileURL)
                    defer { try? fileHandle.close() }
                    try fileHandle.seekToEnd()
                    if let data = logMessage.data(using: .utf8) {
                        try fileHandle.write(contentsOf: data)
                    }
                } else {
                    try logMessage.write(to: logFileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                if logToStderr {
                    fputs("Logger write failed: \(error.localizedDescription)\n", stderr)
                }
            }
        }
    }

    func info(_ message: String) {
        log(message, level: .info)
    }

    func error(_ message: String) {
        log(message, level: .error)
    }

    func debug(_ message: String) {
        log(message, level: .debug)
    }

    func openLogFile() {
        guard let logFileURL else { return }
        NSWorkspace.shared.open(logFileURL)
    }

    deinit {
        log("RubberDuck application terminated", level: .info)
    }

    private static func resolveMinimumLevel(processInfo: ProcessInfo) -> LogLevel {
        if let level = parseLogLevel(processInfo.environment[logLevelEnv]) {
            return level
        }
        return .info
    }

    private static func resolveLogFileURL(
        fileManager: FileManager,
        processInfo: ProcessInfo
    ) -> URL? {
        if parseBool(processInfo.environment[disableFileLoggingEnv]) == true {
            return nil
        }

        if let overridePath = processInfo.environment[logPathOverrideEnv]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: false)
        }

        if AppSupportPaths.isRunningTests(processInfo: processInfo) {
            let rawSessionID = processInfo.environment["XCTestSessionIdentifier"] ?? UUID().uuidString
            let sessionID = sanitizePathComponent(rawSessionID)
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("RubberDuckTests", isDirectory: true)
                .appendingPathComponent("RubberDuck-\(sessionID).log", isDirectory: false)
        }

        return AppSupportPaths.logFileURL(fileManager: fileManager, processInfo: processInfo)
    }

    private static func parseLogLevel(_ raw: String?) -> LogLevel? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "debug":
            return .debug
        case "info":
            return .info
        case "error":
            return .error
        default:
            return nil
        }
    }

    private static func parseBool(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    private static func sanitizePathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleanedScalars = raw.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let value = String(cleanedScalars)
        return value.isEmpty ? UUID().uuidString : value
    }
}

// Static functions for easier global access
func logInfo(_ message: String) {
    Logger.shared.info(message)
}

func logError(_ message: String) {
    Logger.shared.error(message)
}

func logDebug(_ message: String) {
    Logger.shared.debug(message)
}
