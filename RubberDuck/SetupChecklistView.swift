import SwiftUI

struct SetupChecklistView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var configManager: AppConfigManager
    @ObservedObject var cliInstaller: CLIInstaller = .shared

    @State private var pollTimer: Timer?

    private var isAPIKeySet: Bool {
        configManager.getAPIKey() != nil
    }

    private var isMicrophoneGranted: Bool {
        audioManager.microphonePermissionState == .granted
    }

    private var isCLIReady: Bool {
        if case .notBundled = cliInstaller.status { return true } // skip in dev builds
        return cliInstaller.isInstalled
    }

    private var allStepsComplete: Bool {
        isAPIKeySet && isMicrophoneGranted && isCLIReady
    }

    var body: some View {
        setupSteps
            .onAppear { startPolling() }
            .onDisappear { stopPolling() }
    }

    @ViewBuilder
    private var setupSteps: some View {
        Text("Finish Setup")

        if isAPIKeySet {
            Label("OpenAI API key configured", systemImage: "checkmark.circle.fill")
        } else {
            Label("OpenAI API key required", systemImage: "exclamationmark.circle.fill")
            Button("Add API Key...") {
                SettingsWindowController.shared.show()
            }
            Link("Get API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
        }

        if isMicrophoneGranted {
            Label("Microphone access allowed", systemImage: "checkmark.circle.fill")
        } else {
            Label("Microphone access required", systemImage: "mic.slash.fill")
            Button(microphoneActionLabel) {
                handleMicrophoneAction()
            }
        }

        cliInstallStep

        Divider()

        if allStepsComplete {
            Button("Get Started") {
                configManager.setupGuideDismissed = true
            }
        }

        Button("Skip for Now") {
            configManager.setupGuideDismissed = true
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    @ViewBuilder
    private var cliInstallStep: some View {
        switch cliInstaller.status {
        case .notBundled:
            EmptyView() // dev build without embed-cli — omit
        case .installed:
            Label("CLI tools installed", systemImage: "checkmark.circle.fill")
        case .notInstalled, .stale:
            Label("Install CLI tools", systemImage: "terminal")
            Button("Install rubber-duck CLI") {
                cliInstaller.install()
            }
            Text("Makes `rubber-duck` available in your terminal")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error(let msg):
            Label(msg, systemImage: "xmark.circle")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Permission Polling

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                audioManager.refreshMicrophonePermissionState()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Microphone Actions

    private var microphoneActionLabel: String {
        switch audioManager.microphonePermissionState {
        case .granted: return "Granted"
        case .notDetermined: return "Allow Microphone..."
        case .denied, .restricted: return "Open Microphone Settings..."
        }
    }

    private func handleMicrophoneAction() {
        switch audioManager.microphonePermissionState {
        case .granted:
            audioManager.refreshMicrophonePermissionState()
        case .notDetermined:
            audioManager.requestMicrophonePermissionIfNeeded { _ in
                audioManager.refreshMicrophonePermissionState()
            }
        case .denied, .restricted:
            audioManager.openMicrophoneSettings()
        }
    }
}
