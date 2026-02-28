import XCTest
@testable import RubberDuck

final class ToolExecutorFindFilesTests: XCTestCase {

    func test_findFiles_matchesRootFileWithDoubleStarSlashStarPattern() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToolExecutorFindFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let readmeURL = tempRoot.appendingPathComponent("readme.md", isDirectory: false)
        try "hello".write(to: readmeURL, atomically: true, encoding: .utf8)

        let executor = ToolExecutor(workspace: WorkspaceContext(rootPath: tempRoot))
        let result = executor.execute(toolName: "find_files", arguments: #"{"pattern":"**/*"}"#)

        XCTAssertTrue(result.contains("readme.md"), "Expected root file to match '**/*', got: \(result)")
    }
}
