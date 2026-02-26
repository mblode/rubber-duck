import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var transcriptionManager: TranscriptionManager
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var workspaceManager: WorkspaceManager

    private var hasAPIKey: Bool {
        transcriptionManager.getAPIKey() != nil
    }

    private var shouldShowSetupChecklist: Bool {
        !transcriptionManager.setupGuideDismissed
    }

    private var statusSymbolName: String {
        if !hasAPIKey || !transcriptionManager.statusMessage.isEmpty {
            return "exclamationmark.circle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }

    private var statusText: String {
        if !hasAPIKey {
            return "Add API key in Settings"
        }
        if !transcriptionManager.statusMessage.isEmpty {
            return transcriptionManager.statusMessage
        }
        return "Ready"
    }

    private func handleStatusAction() {
        if !hasAPIKey {
            SettingsWindowController.shared.show()
            return
        }

        if !transcriptionManager.statusMessage.isEmpty {
            Logger.shared.openLogFile()
            return
        }

        SettingsWindowController.shared.show()
    }

    private func attachWorkspaceFromPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Attach"
        panel.message = "Choose a workspace folder for voice coding tools."

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        workspaceManager.attachWorkspace(path: selectedURL)
    }

    private func sessionLabel(_ session: SessionRecord) -> String {
        if session.id == workspaceManager.activeSession?.id {
            return "✓ \(session.name)"
        }
        return session.name
    }

    private func workspaceLabel(_ workspace: WorkspaceRecord) -> String {
        if workspace.id == workspaceManager.activeWorkspace?.id {
            return "✓ \(workspace.displayName)"
        }
        return workspace.displayName
    }

    var body: some View {
        if shouldShowSetupChecklist {
            SetupChecklistView(
                audioManager: audioManager,
                transcriptionManager: transcriptionManager
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

        Divider()

        Button("Record shortcut: \(hotkeyManager.shortcutDisplay)") {
            SettingsWindowController.shared.show()
        }

        Divider()

        if let workspace = workspaceManager.activeWorkspace {
            Text("Workspace: \(workspace.displayName)")
            Text(workspace.path)
                .font(.caption)
            if let session = workspaceManager.activeSession {
                Text("Session: \(session.name)")
                    .font(.caption)
            }
        } else {
            Text("No workspace attached")
                .foregroundStyle(.secondary)
        }

        Button("Attach Workspace...") {
            attachWorkspaceFromPicker()
        }

        if workspaceManager.activeWorkspace != nil {
            Button("New Session") {
                workspaceManager.createSession()
            }

            Menu("Switch Session") {
                if workspaceManager.sessionsForActiveWorkspace.isEmpty {
                    Text("No sessions")
                } else {
                    ForEach(workspaceManager.sessionsForActiveWorkspace) { session in
                        Button(sessionLabel(session)) {
                            workspaceManager.switchSession(id: session.id)
                        }
                    }
                }
            }
        }

        if !workspaceManager.workspaces.isEmpty {
            Menu("Switch Workspace") {
                ForEach(workspaceManager.workspaces) { workspace in
                    Button(workspaceLabel(workspace)) {
                        workspaceManager.switchWorkspace(id: workspace.id)
                    }
                }
            }
        }

        Divider()

        Button("Settings...") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Show Logs") {
            Logger.shared.openLogFile()
        }

        Button("Check for Updates...") {
            updateManager.checkForUpdates()
        }
        .disabled(!updateManager.canCheckForUpdates)

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
