import Foundation

/// Manages installing/uninstalling the `rubber-duck` CLI symlinks in /usr/local/bin.
@MainActor
final class CLIInstaller: ObservableObject {

    enum Status: Equatable {
        case notBundled           // dev build — binary not embedded via make embed-cli
        case notInstalled         // binary present but symlink not created yet
        case installed(version: String)  // symlink exists and points to this app's binary
        case stale               // symlink points elsewhere (moved app / old version)
        case error(String)
    }

    static let shared = CLIInstaller()

    @Published private(set) var status: Status = .notBundled

    private let binDir      = URL(fileURLWithPath: "/usr/local/bin")
    private var cliLink:    URL { binDir.appendingPathComponent("rubber-duck") }
    private var daemonLink: URL { binDir.appendingPathComponent("rubber-duck-daemon") }

    private init() { refresh() }

    func refresh() {
        guard let bundled = AppSupportPaths.bundledCLIURL() else {
            status = .notBundled
            return
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: cliLink.path) else {
            status = .notInstalled
            return
        }
        let resolved = try? fm.destinationOfSymbolicLink(atPath: cliLink.path)
        let resolvedURL = resolved.map { URL(fileURLWithPath: $0).standardizedFileURL }
        if resolvedURL == bundled.standardizedFileURL {
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            status = .installed(version: v)
        } else {
            status = .stale
        }
    }

    /// Creates /usr/local/bin/rubber-duck and /usr/local/bin/rubber-duck-daemon symlinks.
    /// Returns nil on success, or an error message on failure.
    @discardableResult
    func install() -> String? {
        guard let bundled = AppSupportPaths.bundledCLIURL() else {
            return "Binary not found in app bundle"
        }
        let fm = FileManager.default

        if !fm.fileExists(atPath: binDir.path) {
            do {
                try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
            } catch {
                return "Cannot create /usr/local/bin: \(error.localizedDescription)"
            }
        }

        guard fm.isWritableFile(atPath: binDir.path) else {
            return "/usr/local/bin is not writable. Run manually:\nsudo ln -sfn \"\(bundled.path)\" /usr/local/bin/rubber-duck"
        }

        for link in [cliLink, daemonLink] {
            try? fm.removeItem(at: link)
        }

        do {
            try fm.createSymbolicLink(at: cliLink,    withDestinationURL: bundled)
            try fm.createSymbolicLink(at: daemonLink, withDestinationURL: bundled)
        } catch {
            return "Symlink failed: \(error.localizedDescription)"
        }

        logInfo("CLIInstaller: installed rubber-duck → \(bundled.path)")
        refresh()
        return nil
    }

    func uninstall() {
        for link in [cliLink, daemonLink] {
            try? FileManager.default.removeItem(at: link)
        }
        refresh()
    }

    var isInstalled: Bool {
        if case .installed = status { return true }
        return false
    }
}
