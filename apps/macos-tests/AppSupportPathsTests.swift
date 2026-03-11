import XCTest
@testable import RubberDuck

final class AppSupportPathsTests: XCTestCase {

    func test_resolveRootURL_prefersOverride() {
        let standard = URL(fileURLWithPath: "/standard", isDirectory: true)
        let legacy = URL(fileURLWithPath: "/legacy", isDirectory: true)

        let resolved = AppSupportPaths.resolveRootURL(
            override: " /tmp/custom-path ",
            standardRoot: standard,
            legacyContainerRoot: legacy,
            fileExists: { _ in false }
        )

        XCTAssertEqual(resolved.path, "/tmp/custom-path")
    }

    func test_resolveRootURL_prefersStandardWhenBothExist() {
        let standard = URL(fileURLWithPath: "/standard", isDirectory: true)
        let legacy = URL(fileURLWithPath: "/legacy", isDirectory: true)

        let resolved = AppSupportPaths.resolveRootURL(
            override: nil,
            standardRoot: standard,
            legacyContainerRoot: legacy,
            fileExists: { path in path == "/standard" || path == "/legacy" }
        )

        XCTAssertEqual(resolved.path, "/standard")
    }

    func test_resolveRootURL_usesLegacyWhenStandardMissing() {
        let standard = URL(fileURLWithPath: "/standard", isDirectory: true)
        let legacy = URL(fileURLWithPath: "/legacy", isDirectory: true)

        let resolved = AppSupportPaths.resolveRootURL(
            override: nil,
            standardRoot: standard,
            legacyContainerRoot: legacy,
            fileExists: { $0 == "/legacy" }
        )

        XCTAssertEqual(resolved.path, "/legacy")
    }

    func test_resolveRootURL_defaultsToStandardWhenNoPathExists() {
        let standard = URL(fileURLWithPath: "/standard", isDirectory: true)
        let legacy = URL(fileURLWithPath: "/legacy", isDirectory: true)

        let resolved = AppSupportPaths.resolveRootURL(
            override: nil,
            standardRoot: standard,
            legacyContainerRoot: legacy,
            fileExists: { _ in false }
        )

        XCTAssertEqual(resolved.path, "/standard")
    }
}
