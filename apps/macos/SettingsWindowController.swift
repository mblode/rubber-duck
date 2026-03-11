import SwiftUI
import AppKit

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private weak var configManager: AppConfigManager?
    private weak var audioManager: AudioManager?
    private weak var updateManager: UpdateManager?
    private var windowController: NSWindowController?

    private init() {}

    func configure(
        configManager: AppConfigManager,
        audioManager: AudioManager,
        updateManager: UpdateManager
    ) {
        self.configManager = configManager
        self.audioManager = audioManager
        self.updateManager = updateManager

        if let window = windowController?.window,
           let storedAudioManager = self.audioManager,
           let storedUpdateManager = self.updateManager {
            window.contentViewController = NSHostingController(
                rootView: SettingsView()
                    .environmentObject(configManager)
                    .environmentObject(storedAudioManager)
                    .environmentObject(storedUpdateManager)
            )
        }
    }

    func show() {
        guard let configManager, let audioManager, let updateManager else {
            logError("SettingsWindowController: Missing managers")
            return
        }

        let controller: NSWindowController
        if let existing = windowController {
            controller = existing
        } else {
            controller = makeWindowController(
                configManager: configManager,
                audioManager: audioManager,
                updateManager: updateManager
            )
            windowController = controller
        }

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindowController(
        configManager: AppConfigManager,
        audioManager: AudioManager,
        updateManager: UpdateManager
    ) -> NSWindowController {
        let hostingController = NSHostingController(
            rootView: SettingsView()
                .environmentObject(configManager)
                .environmentObject(audioManager)
                .environmentObject(updateManager)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("RubberDuckSettingsWindow")
        window.center()

        return NSWindowController(window: window)
    }
}
