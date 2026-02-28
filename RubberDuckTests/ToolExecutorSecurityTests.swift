import XCTest
@testable import RubberDuck

final class ToolExecutorSecurityTests: XCTestCase {

    func test_resolvedPath_rejectsAbsoluteSiblingPrefixTraversal() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let workspaceRoot = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let siblingRoot = tempRoot.appendingPathComponent("workspace-escape", isDirectory: true)
        let siblingFile = siblingRoot.appendingPathComponent("secret.txt", isDirectory: false)

        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: siblingRoot, withIntermediateDirectories: true)
        try "secret".write(to: siblingFile, atomically: true, encoding: .utf8)

        let result = resolvedPath(
            for: siblingFile.path,
            workspace: WorkspaceContext(rootPath: workspaceRoot)
        )

        guard case .failure(.escapesWorkspace) = result else {
            return XCTFail("Expected sibling prefix traversal to be rejected, got: \(result)")
        }
    }

    func test_writeFile_rejectsSymlinkEscapeOutsideWorkspace() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let workspaceRoot = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let outsideRoot = tempRoot.appendingPathComponent("outside", isDirectory: true)
        let escapeLink = workspaceRoot.appendingPathComponent("escape", isDirectory: true)

        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: escapeLink.path,
            withDestinationPath: outsideRoot.path
        )

        let executor = ToolExecutor(workspace: WorkspaceContext(rootPath: workspaceRoot))
        let result = try execute(
            executor,
            tool: ToolName.writeFile,
            arguments: [
                "path": "escape/pwned.txt",
                "content": "owned"
            ]
        )

        XCTAssertEqual(result, "Error: Path escapes workspace root")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outsideRoot.appendingPathComponent("pwned.txt").path),
            "Write through a workspace symlink should not escape into outside directories"
        )
    }

    func test_bashSafeMode_doesNotExecuteShellCommandChains() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let executor = ToolExecutor(workspace: WorkspaceContext(rootPath: tempRoot))
        executor.safeMode = true

        let chainedWriteURL = tempRoot.appendingPathComponent("chained.txt", isDirectory: false)
        let result = try execute(
            executor,
            tool: ToolName.bash,
            arguments: ["command": "ls ; touch chained.txt"]
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: chainedWriteURL.path),
            "Safe mode must not execute shell chains like '; touch ...'"
        )
        XCTAssertTrue(result.contains("[Exit code:") || result.contains("Error: Command not allowed in safe mode"))
    }

    func test_grepSearch_returnsNoMatchesForExitCodeOne() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("sample.txt", isDirectory: false)
        try "hello world".write(to: fileURL, atomically: true, encoding: .utf8)

        let executor = ToolExecutor(workspace: WorkspaceContext(rootPath: tempRoot))
        let result = try execute(
            executor,
            tool: ToolName.grepSearch,
            arguments: ["pattern": "does-not-exist-needle"]
        )

        XCTAssertEqual(result, "No matches found")
    }

    func test_grepSearch_surfacesStderrForRealFailures() throws {
        let tempRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("sample.txt", isDirectory: false)
        try "hello world".write(to: fileURL, atomically: true, encoding: .utf8)

        let executor = ToolExecutor(workspace: WorkspaceContext(rootPath: tempRoot))
        let result = try execute(
            executor,
            tool: ToolName.grepSearch,
            arguments: ["pattern": "["]
        )

        XCTAssertTrue(result.hasPrefix("Error: grep failed with exit code"), "Unexpected result: \(result)")
        XCTAssertFalse(result.contains("No matches found"))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToolExecutorSecurityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func execute(_ executor: ToolExecutor, tool: String, arguments: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        return executor.execute(toolName: tool, arguments: json)
    }
}
