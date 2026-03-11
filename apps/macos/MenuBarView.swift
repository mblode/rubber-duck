import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var configManager: AppConfigManager
    @ObservedObject var workspaceManager: WorkspaceManager

    private var hasAPIKey: Bool {
        configManager.getAPIKey() != nil
    }

    private var shouldShowSetupChecklist: Bool {
        !configManager.setupGuideDismissed
    }

    private var statusSymbolName: String {
        if !hasAPIKey || !configManager.statusMessage.isEmpty {
            return "exclamationmark.circle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }

    private var statusText: String {
        if !hasAPIKey {
            return "Add API key in Settings"
        }
        if !configManager.statusMessage.isEmpty {
            return configManager.statusMessage
        }
        return "Ready"
    }

    private func handleStatusAction() {
        if !hasAPIKey {
            SettingsWindowController.shared.show()
            return
        }

        if !configManager.statusMessage.isEmpty {
            Logger.shared.openLogFile()
            return
        }

        SettingsWindowController.shared.show()
    }

    var body: some View {
        if shouldShowSetupChecklist {
            SetupChecklistView(
                audioManager: audioManager,
                configManager: configManager
            )
        } else {
            normalMenuContent
        }
    }

    @ViewBuilder
    private var normalMenuContent: some View {
        Button(action: handleStatusAction) {
            Label(statusText, systemImage: statusSymbolName)
        }

        Text("Activate: \(hotkeyManager.shortcutDisplay)")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        if let workspace = workspaceManager.activeWorkspace {
            Text("Workspace: \(workspace.displayName)")
            if let session = workspaceManager.activeSession {
                Text("Session: \(session.name)")
                    .font(.caption)
            }
        } else {
            Text("No workspace attached")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Settings...") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
