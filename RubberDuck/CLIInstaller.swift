import Foundation

/// Downloads and manages the `duck` CLI binary in Application Support.
///
/// On first launch the app downloads the matching arch binary from GitHub Releases
/// into ~/Library/Application Support/RubberDuck/duck, then symlinks
/// /usr/local/bin/duck and /usr/local/bin/duck-daemon to it.
/// On subsequent app updates, a version mismatch triggers an auto-redownload.
@MainActor
final class CLIInstaller: ObservableObject {

    enum Status: Equatable {
        case notInstalled
        case downloading(progress: Double)
        case installed(version: String)
        case updateAvailable(installedVersion: String, newVersion: String)
        case error(String)
    }

    static let shared = CLIInstaller()

    @Published private(set) var status: Status = .notInstalled

    private let binDir      = URL(fileURLWithPath: "/usr/local/bin")
    private var cliLink:    URL { binDir.appendingPathComponent("duck") }
    private var daemonLink: URL { binDir.appendingPathComponent("duck-daemon") }

    private var installedBinaryURL: URL {
        AppSupportPaths.rootURL().appendingPathComponent("duck")
    }
    private var versionFileURL: URL {
        AppSupportPaths.rootURL().appendingPathComponent("duck.version")
    }

    private init() { refresh() }

    func refresh() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: installedBinaryURL.path),
              fm.isExecutableFile(atPath: installedBinaryURL.path) else {
            status = .notInstalled
            return
        }
        // Binary exists — also verify the symlink resolves to a live target.
        if !fm.fileExists(atPath: cliLink.path) {
            status = .error("Symlink missing. Run:\nsudo ln -sfn \"\(installedBinaryURL.path)\" /usr/local/bin/duck")
            return
        }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let installedVersion = (try? String(contentsOf: versionFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        if installedVersion == appVersion || installedVersion.isEmpty {
            status = .installed(version: installedVersion.isEmpty ? appVersion : installedVersion)
        } else {
            status = .updateAvailable(installedVersion: installedVersion, newVersion: appVersion)
        }
    }

    /// Downloads the CLI binary matching the current app version from GitHub Releases,
    /// writes it to Application Support, strips quarantine, and symlinks to /usr/local/bin.
    func install() async {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        #if arch(arm64)
        let assetName = "duck-\(appVersion)-macos-arm64"
        #else
        let assetName = "duck-\(appVersion)-macos-x64"
        #endif
        guard let downloadURL = URL(string:
            "https://github.com/mblode/rubber-duck/releases/download/v\(appVersion)/\(assetName)")
        else {
            status = .error("Invalid download URL")
            return
        }

        status = .downloading(progress: 0)
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: downloadURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                status = .error("Download failed: HTTP \(http.statusCode)")
                return
            }
            let fm = FileManager.default
            let destURL = installedBinaryURL
            try? fm.removeItem(at: destURL)
            try fm.moveItem(at: tempURL, to: destURL)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
            await Task.detached(priority: .userInitiated) { Self.stripQuarantine(destURL) }.value
            try appVersion.write(to: versionFileURL, atomically: true, encoding: .utf8)
            if let err = createSymlinks() {
                logInfo("CLIInstaller: symlink: \(err)")
                status = .error(err)
                return
            }
            logInfo("CLIInstaller: installed duck v\(appVersion)")
            refresh()
        } catch {
            status = .error("Download failed: \(error.localizedDescription)")
        }
    }

    func uninstall() {
        for link in [cliLink, daemonLink] {
            try? FileManager.default.removeItem(at: link)
        }
        try? FileManager.default.removeItem(at: installedBinaryURL)
        try? FileManager.default.removeItem(at: versionFileURL)
        refresh()
    }

    var isInstalled: Bool {
        switch status {
        case .installed, .updateAvailable: return true
        default: return false
        }
    }

    // MARK: - Private helpers

    private nonisolated static func stripQuarantine(_ url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-d", "com.apple.quarantine", url.path]
        try? task.run()
        task.waitUntilExit()
    }

    /// Creates /usr/local/bin symlinks pointing to the installed binary.
    /// Returns nil on success, or an error description on failure.
    private func createSymlinks() -> String? {
        let fm = FileManager.default
        if !fm.fileExists(atPath: binDir.path) {
            do {
                try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
            } catch {
                return "Cannot create /usr/local/bin: \(error.localizedDescription)"
            }
        }
        guard fm.isWritableFile(atPath: binDir.path) else {
            return "/usr/local/bin is not writable. Run manually:\nsudo ln -sfn \"\(installedBinaryURL.path)\" /usr/local/bin/duck"
        }
        for link in [cliLink, daemonLink] {
            try? fm.removeItem(at: link)
        }
        do {
            try fm.createSymbolicLink(at: cliLink,    withDestinationURL: installedBinaryURL)
            try fm.createSymbolicLink(at: daemonLink, withDestinationURL: installedBinaryURL)
        } catch {
            return "Symlink failed: \(error.localizedDescription)"
        }
        return nil
    }
}
