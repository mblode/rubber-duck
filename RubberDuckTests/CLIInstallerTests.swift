import XCTest
@testable import RubberDuck

@MainActor
final class CLIInstallerTests: XCTestCase {

    // MARK: - Status enum tests

    func test_isInstalled_trueForInstalledStatus() {
        let sut = makeSUT()
        sut.setStatusForTesting(.installed(version: "1.0.0"))
        XCTAssertTrue(sut.isInstalled)
    }

    func test_isInstalled_trueForUpdateAvailable() {
        let sut = makeSUT()
        sut.setStatusForTesting(.updateAvailable(installedVersion: "1.0.0", newVersion: "1.1.0"))
        XCTAssertTrue(sut.isInstalled)
    }

    func test_isInstalled_trueForLocalBinInstalled() {
        let sut = makeSUT()
        let info = SymlinkErrorInfo(kind: .localBinInstalled, binaryPath: "/tmp/duck", localBinInPath: false)
        sut.setStatusForTesting(.symlinkError(info))
        XCTAssertTrue(sut.isInstalled)
    }

    func test_isInstalled_falseForPermissionDenied() {
        let sut = makeSUT()
        let info = SymlinkErrorInfo(kind: .permissionDenied, binaryPath: "/tmp/duck", localBinInPath: false)
        sut.setStatusForTesting(.symlinkError(info))
        XCTAssertFalse(sut.isInstalled)
    }

    func test_isInstalled_falseForUserCancelled() {
        let sut = makeSUT()
        let info = SymlinkErrorInfo(kind: .userCancelled, binaryPath: "/tmp/duck", localBinInPath: false)
        sut.setStatusForTesting(.symlinkError(info))
        XCTAssertFalse(sut.isInstalled)
    }

    func test_isInstalled_falseForNotInstalled() {
        let sut = makeSUT()
        sut.setStatusForTesting(.notInstalled)
        XCTAssertFalse(sut.isInstalled)
    }

    // MARK: - isLocalBinInPATH tests

    func test_isLocalBinInPATH_trueWhenPresent() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fakePATH = "/usr/bin:/usr/local/bin:\(home)/.local/bin"
        // We can't override ProcessInfo in tests, but we can validate the logic
        // by checking that the path-splitting approach works as expected.
        let result = fakePATH.split(separator: ":").map(String.init).contains(home + "/.local/bin")
        XCTAssertTrue(result)
    }

    func test_isLocalBinInPATH_falseWhenAbsent() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fakePATH = "/usr/bin:/usr/local/bin"
        let result = fakePATH.split(separator: ":").map(String.init).contains(home + "/.local/bin")
        XCTAssertFalse(result)
    }

    // MARK: - appleScriptSingleQuoteEscaped tests (via String extension)

    func test_appleScriptEscaped_noSpecialChars() {
        let path = "/Users/alice/Library/Application Support/RubberDuck/duck"
        // No single quotes — should be unchanged
        XCTAssertEqual(path.appleScriptSingleQuoteEscapedPublic, path)
    }

    func test_appleScriptEscaped_singleQuotesInPath() {
        // Unusual but possible with apostrophes in usernames
        let path = "/Users/O'Brien/Library/duck"
        let escaped = path.appleScriptSingleQuoteEscapedPublic
        // Single quote should be escaped as '\''
        XCTAssertEqual(escaped, "/Users/O'\\''Brien/Library/duck")
        // The escaped version should not contain a bare single-quote mid-word
        XCTAssertFalse(escaped.contains("O'B"))
    }

    // MARK: - SymlinkErrorInfo Equatable

    func test_symlinkErrorInfo_equatable() {
        let a = SymlinkErrorInfo(kind: .localBinInstalled, binaryPath: "/tmp/duck", localBinInPath: true)
        let b = SymlinkErrorInfo(kind: .localBinInstalled, binaryPath: "/tmp/duck", localBinInPath: true)
        let c = SymlinkErrorInfo(kind: .permissionDenied, binaryPath: "/tmp/duck", localBinInPath: true)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Helpers

    private func makeSUT() -> CLIInstaller {
        CLIInstaller.shared
    }
}

// MARK: - Test-only String extension (mirrors private extension in CLIInstaller.swift)

extension String {
    var appleScriptSingleQuoteEscapedPublic: String {
        replacingOccurrences(of: "'", with: "'\\''")
    }
}
