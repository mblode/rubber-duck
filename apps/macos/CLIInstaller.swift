import Foundation

// MARK: - SymlinkErrorInfo

struct SymlinkErrorInfo: Equatable {
    enum Kind: Equatable {
        case localBinInstalled  // succeeded via ~/.local/bin; PATH reminder may be needed
        case userCancelled      // osascript auth cancelled; offer ~/.local/bin explicitly
        case permissionDenied   // both paths failed; show manual sudo command
    }
    let kind: Kind
    let binaryPath: String   // absolute path to the installed binary (for copy)
    let localBinInPath: Bool // whether ~/.local/bin is already on $PATH
}

// MARK: - CLIInstaller

/// Downloads and manages the `duck` CLI binary in Application Support.
///
/// Installation waterfall:
/// 1. Try silent symlink to /usr/local/bin (works when user-owned, e.g. Homebrew legacy)
/// 2. If not writable: show osascript admin dialog (VS Code approach)
/// 3. If admin cancelled: offer ~/.local/bin as no-sudo fallback
@MainActor
final class CLIInstaller: ObservableObject {

    enum Status: Equatable {
        case notInstalled
        case downloading(progress: Double)
        case installed(version: String)
        case updateAvailable(installedVersion: String, newVersion: String)
        case error(String)                  // download / network failures
        case symlinkError(SymlinkErrorInfo) // post-download PATH-integration failures
    }

    // Internal-only: tracks result of each symlink phase
    private enum SymlinkResult {
        case success
        case needsElevation      // /usr/local/bin not writable
        case cancelledByUser     // osascript error -128 (user clicked Cancel)
        case localBinFallback    // ~/.local/bin symlinks written OK
        case failed(String)
    }

    static let shared = CLIInstaller()

    @Published private(set) var status: Status = .notInstalled

    private let usrLocalBin = URL(fileURLWithPath: "/usr/local/bin")
    private var cliLink:    URL { usrLocalBin.appendingPathComponent("duck") }
    private var daemonLink: URL { usrLocalBin.appendingPathComponent("duck-daemon") }

    private var localBinDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
    }
    private var localCLILink:    URL { localBinDir.appendingPathComponent("duck") }
    private var localDaemonLink: URL { localBinDir.appendingPathComponent("duck-daemon") }

    private var installedBinaryURL: URL {
        AppSupportPaths.rootURL().appendingPathComponent("duck")
    }
    private var versionFileURL: URL {
        AppSupportPaths.rootURL().appendingPathComponent("duck.version")
    }

    private init() { refresh() }

    // MARK: - Public API

    func refresh() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: installedBinaryURL.path),
              fm.isExecutableFile(atPath: installedBinaryURL.path) else {
            status = .notInstalled
            return
        }
        // Binary exists — check if any known symlink location resolves
        let hasUsrLocal = fm.fileExists(atPath: cliLink.path)
        let hasLocalBin = fm.fileExists(atPath: localCLILink.path)
        if !hasUsrLocal && !hasLocalBin {
            status = .symlinkError(SymlinkErrorInfo(
                kind: .permissionDenied,
                binaryPath: installedBinaryURL.path,
                localBinInPath: Self.isLocalBinInPATH()
            ))
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

    /// Downloads the CLI binary from GitHub Releases, installs it, and creates symlinks.
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

            let result = await createSymlinks()
            switch result {
            case .success:
                logInfo("CLIInstaller: installed duck v\(appVersion) → /usr/local/bin")
                refresh()
            case .needsElevation, .cancelledByUser:
                // /usr/local/bin not writable or user cancelled auth — try ~/.local/bin
                let localResult = createLocalBinSymlinks()
                applyLocalBinResult(localResult, version: appVersion)
            case .localBinFallback:
                applyLocalBinResult(result, version: appVersion)
            case .failed(let msg):
                logInfo("CLIInstaller: symlink failed: \(msg)")
                status = .symlinkError(SymlinkErrorInfo(
                    kind: .permissionDenied,
                    binaryPath: installedBinaryURL.path,
                    localBinInPath: Self.isLocalBinInPATH()
                ))
            }
        } catch {
            status = .error("Download failed: \(error.localizedDescription)")
        }
    }

    /// Skips /usr/local/bin and installs symlinks directly to ~/.local/bin.
    /// Called when the user declines admin elevation.
    func installToLocalBin() async {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let result = createLocalBinSymlinks()
        applyLocalBinResult(result, version: appVersion)
    }

    func uninstall() {
        let toRemove: [URL] = [
            cliLink, daemonLink,
            localCLILink, localDaemonLink,
            installedBinaryURL, versionFileURL
        ]
        for url in toRemove { try? FileManager.default.removeItem(at: url) }
        refresh()
    }

    var isInstalled: Bool {
        switch status {
        case .installed, .updateAvailable: return true
        case .symlinkError(let info) where info.kind == .localBinInstalled: return true
        default: return false
        }
    }

    // MARK: - Private helpers

    /// Three-phase: (A) silent /usr/local/bin, (B) osascript elevation.
    /// Returns .needsElevation / .cancelledByUser if caller should try ~/.local/bin.
    private func createSymlinks() async -> SymlinkResult {
        let fm = FileManager.default

        // Phase A: silent /usr/local/bin
        if !fm.fileExists(atPath: usrLocalBin.path) {
            try? fm.createDirectory(at: usrLocalBin, withIntermediateDirectories: true)
        }
        if fm.isWritableFile(atPath: usrLocalBin.path) {
            for link in [cliLink, daemonLink] { try? fm.removeItem(at: link) }
            do {
                try fm.createSymbolicLink(at: cliLink,    withDestinationURL: installedBinaryURL)
                try fm.createSymbolicLink(at: daemonLink, withDestinationURL: installedBinaryURL)
                return .success
            } catch {
                return .failed("Symlink failed: \(error.localizedDescription)")
            }
        }

        // Phase B: osascript elevation (VS Code approach)
        let src = installedBinaryURL.path.appleScriptSingleQuoteEscaped
        let shellCmd = "rm -f '/usr/local/bin/duck' '/usr/local/bin/duck-daemon'"
            + " && ln -sfn '\(src)' '/usr/local/bin/duck'"
            + " && ln -sfn '\(src)' '/usr/local/bin/duck-daemon'"
        let appleScript = "do shell script \"\(shellCmd)\" with administrator privileges"

        // Run NSAppleScript (blocking) on a background thread; extract only the Int error code
        // to avoid Swift 6 Sendable issues with NSDictionary crossing actor boundaries.
        let errorCode: Int? = await Task.detached(priority: .userInitiated) {
            var errorInfo: NSDictionary?
            NSAppleScript(source: appleScript)?.executeAndReturnError(&errorInfo)
            guard let d = errorInfo else { return nil }
            return (d[NSAppleScript.errorNumber] as? Int) ?? -1
        }.value

        if let code = errorCode {
            if code == -128 { return .cancelledByUser }
            logInfo("CLIInstaller: osascript error \(code)")
            return .needsElevation
        }
        return .success
    }

    /// Writes symlinks to ~/.local/bin (no privileges required).
    private func createLocalBinSymlinks() -> SymlinkResult {
        let fm = FileManager.default
        if !fm.fileExists(atPath: localBinDir.path) {
            do {
                try fm.createDirectory(at: localBinDir, withIntermediateDirectories: true)
            } catch {
                return .failed("Cannot create ~/.local/bin: \(error.localizedDescription)")
            }
        }
        for link in [localCLILink, localDaemonLink] { try? fm.removeItem(at: link) }
        do {
            try fm.createSymbolicLink(at: localCLILink,    withDestinationURL: installedBinaryURL)
            try fm.createSymbolicLink(at: localDaemonLink, withDestinationURL: installedBinaryURL)
        } catch {
            return .failed("Symlink failed: \(error.localizedDescription)")
        }
        return .localBinFallback
    }

    private func applyLocalBinResult(_ result: SymlinkResult, version: String) {
        switch result {
        case .localBinFallback:
            let inPath = Self.isLocalBinInPATH()
            logInfo("CLIInstaller: installed duck to ~/.local/bin, inPath=\(inPath)")
            try? version.write(to: versionFileURL, atomically: true, encoding: .utf8)
            status = .symlinkError(SymlinkErrorInfo(
                kind: .localBinInstalled,
                binaryPath: localCLILink.path,
                localBinInPath: inPath
            ))
        case .failed(let msg):
            logInfo("CLIInstaller: local bin fallback failed: \(msg)")
            status = .symlinkError(SymlinkErrorInfo(
                kind: .permissionDenied,
                binaryPath: installedBinaryURL.path,
                localBinInPath: Self.isLocalBinInPATH()
            ))
        default:
            break
        }
    }

    nonisolated static func isLocalBinInPATH() -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.split(separator: ":").map(String.init).contains(home + "/.local/bin")
    }

    private nonisolated static func stripQuarantine(_ url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-d", "com.apple.quarantine", url.path]
        try? task.run()
        task.waitUntilExit()
    }
}

// MARK: - Test support

#if DEBUG
extension CLIInstaller {
    func setStatusForTesting(_ newStatus: Status) {
        status = newStatus
    }
}
#endif

// MARK: - String helper

private extension String {
    /// Escapes single-quotes for use inside a single-quoted shell argument within AppleScript.
    var appleScriptSingleQuoteEscaped: String {
        replacingOccurrences(of: "'", with: "'\\''")
    }
}
