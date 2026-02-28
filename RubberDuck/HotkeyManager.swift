import Foundation
import Cocoa
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording", default: .init(.d, modifiers: [.option]))
    static let openSettings = Self("openSettings", default: .init(.d, modifiers: [.option, .shift]))
}

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyManagerDidDetectKeyDown(_ manager: HotkeyManager)
    func hotkeyManagerDidDetectKeyUp(_ manager: HotkeyManager)
}

@MainActor
class HotkeyManager: ObservableObject {
    static let activateDefaultShortcut = KeyboardShortcuts.Shortcut(.d, modifiers: [.option])
    static let settingsDefaultShortcut = KeyboardShortcuts.Shortcut(.d, modifiers: [.option, .shift])

    @Published var shortcutDisplay: String = ""
    @Published var settingsShortcutDisplay: String = ""
    weak var delegate: HotkeyManagerDelegate?
    private var shortcutChangeObserver: NSObjectProtocol?
    private var isToggleRecordingKeyHeld = false

    init() {
        logInfo("HotkeyManager: Initializing")
        updateShortcutDisplay()
        updateSettingsShortcutDisplay()
        observeShortcutChanges()
        repairShortcutAssignmentsIfNeeded()

        KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [weak self] in
            guard let self else { return }
            guard !self.isToggleRecordingKeyHeld else {
                logDebug("HotkeyManager: Ignoring repeated hotkey key down while held")
                return
            }
            self.isToggleRecordingKeyHeld = true
            logDebug("HotkeyManager: Hotkey key down")
            self.delegate?.hotkeyManagerDidDetectKeyDown(self)
        }

        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            guard let self else { return }
            self.isToggleRecordingKeyHeld = false
            logDebug("HotkeyManager: Hotkey key up")
            self.delegate?.hotkeyManagerDidDetectKeyUp(self)
        }

        KeyboardShortcuts.onKeyUp(for: .openSettings) {
            guard !Self.shortcutsConflict(.openSettings, .toggleRecording) else {
                logInfo("HotkeyManager: Ignoring open settings shortcut because it conflicts with record shortcut")
                return
            }
            logDebug("HotkeyManager: Open settings hotkey key up")
            SettingsWindowController.shared.show()
        }
    }

    deinit {
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }
    }

    private func observeShortcutChanges() {
        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name,
                name == .toggleRecording || name == .openSettings
            else {
                return
            }

            Task { @MainActor [weak self] in
                if name == .toggleRecording {
                    self?.updateShortcutDisplay()
                } else {
                    self?.updateSettingsShortcutDisplay()
                }
                self?.repairShortcutAssignmentsIfNeeded()
            }
        }
    }

    func updateShortcutDisplay() {
        shortcutDisplay = Self.displayString(for: .toggleRecording)
    }

    func updateSettingsShortcutDisplay() {
        settingsShortcutDisplay = Self.displayString(for: .openSettings)
    }

    private static func displayString(for name: KeyboardShortcuts.Name) -> String {
        if let shortcut = KeyboardShortcuts.getShortcut(for: name) {
            return formattedShortcut(shortcut)
        }
        return "Not set"
    }

    private static func formattedShortcut(_ shortcut: KeyboardShortcuts.Shortcut) -> String {
        let raw = shortcut.description

        // Replace all four modifier symbols with ✦ (Hyper Key).
        let allModifiers = "\u{2303}\u{2325}\u{21E7}\u{2318}" // ⌃⌥⇧⌘
        if raw.hasPrefix(allModifiers) {
            return "✦" + raw.dropFirst(allModifiers.count)
        }
        return raw
    }

    private static func shortcutsConflict(
        _ lhs: KeyboardShortcuts.Name,
        _ rhs: KeyboardShortcuts.Name
    ) -> Bool {
        guard
            let lhsShortcut = KeyboardShortcuts.getShortcut(for: lhs),
            let rhsShortcut = KeyboardShortcuts.getShortcut(for: rhs)
        else {
            return false
        }

        return lhsShortcut == rhsShortcut
    }

    nonisolated static func repairedShortcuts(
        toggleRecording: KeyboardShortcuts.Shortcut?,
        openSettings: KeyboardShortcuts.Shortcut?
    ) -> (
        toggleRecording: KeyboardShortcuts.Shortcut,
        openSettings: KeyboardShortcuts.Shortcut,
        didRepair: Bool
    ) {
        var repairedToggle: KeyboardShortcuts.Shortcut
        var repairedSettings: KeyboardShortcuts.Shortcut

        if toggleRecording == nil
            || openSettings == activateDefaultShortcut
            || (toggleRecording != nil && openSettings != nil && toggleRecording == openSettings) {
            repairedToggle = activateDefaultShortcut
        } else {
            repairedToggle = toggleRecording!
        }

        if openSettings == nil
            || openSettings == activateDefaultShortcut
            || openSettings == repairedToggle {
            repairedSettings = settingsDefaultShortcut
        } else {
            repairedSettings = openSettings!
        }

        // Enforce a deterministic post-repair invariant: shortcuts must never match.
        // When a final conflict remains, prefer restoring toggle recording to Option+D.
        if repairedToggle == repairedSettings {
            repairedToggle = activateDefaultShortcut
            if repairedSettings == repairedToggle {
                repairedSettings = settingsDefaultShortcut
            }
        }

        let didRepair = repairedToggle != toggleRecording || repairedSettings != openSettings
        return (repairedToggle, repairedSettings, didRepair)
    }

    private func repairShortcutAssignmentsIfNeeded() {
        let currentToggle = KeyboardShortcuts.getShortcut(for: .toggleRecording)
        let currentSettings = KeyboardShortcuts.getShortcut(for: .openSettings)

        let repaired = Self.repairedShortcuts(
            toggleRecording: currentToggle,
            openSettings: currentSettings
        )

        guard repaired.didRepair else {
            return
        }

        KeyboardShortcuts.setShortcut(repaired.toggleRecording, for: .toggleRecording)
        KeyboardShortcuts.setShortcut(repaired.openSettings, for: .openSettings)

        updateShortcutDisplay()
        updateSettingsShortcutDisplay()
        logInfo("HotkeyManager: Repaired shortcut assignments (Activate=Option+D, Open Settings=Option+Shift+D)")
    }
}
