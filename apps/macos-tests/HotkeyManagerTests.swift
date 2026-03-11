import XCTest
import KeyboardShortcuts
@testable import RubberDuck

final class HotkeyManagerTests: XCTestCase {
    func test_repairedShortcuts_fixSettingsStealingOptionD() {
        let repaired = HotkeyManager.repairedShortcuts(
            toggleRecording: KeyboardShortcuts.Shortcut(.d, modifiers: [.option, .shift]),
            openSettings: KeyboardShortcuts.Shortcut(.d, modifiers: [.option])
        )

        XCTAssertEqual(repaired.toggleRecording, HotkeyManager.activateDefaultShortcut)
        XCTAssertEqual(repaired.openSettings, HotkeyManager.settingsDefaultShortcut)
        XCTAssertTrue(repaired.didRepair)
    }

    func test_repairedShortcuts_keepsValidAssignments() {
        let repaired = HotkeyManager.repairedShortcuts(
            toggleRecording: KeyboardShortcuts.Shortcut(.d, modifiers: [.option]),
            openSettings: KeyboardShortcuts.Shortcut(.comma, modifiers: [.option, .shift])
        )

        XCTAssertEqual(repaired.toggleRecording, KeyboardShortcuts.Shortcut(.d, modifiers: [.option]))
        XCTAssertEqual(repaired.openSettings, KeyboardShortcuts.Shortcut(.comma, modifiers: [.option, .shift]))
        XCTAssertFalse(repaired.didRepair)
    }

    func test_repairedShortcuts_enforcesNonConflictWhenSettingsIsNil() {
        let repaired = HotkeyManager.repairedShortcuts(
            toggleRecording: HotkeyManager.settingsDefaultShortcut,
            openSettings: nil
        )

        XCTAssertEqual(repaired.toggleRecording, HotkeyManager.activateDefaultShortcut)
        XCTAssertEqual(repaired.openSettings, HotkeyManager.settingsDefaultShortcut)
        XCTAssertNotEqual(repaired.toggleRecording, repaired.openSettings)
        XCTAssertTrue(repaired.didRepair)
    }
}
