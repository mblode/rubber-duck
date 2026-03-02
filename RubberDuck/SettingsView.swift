import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

// MARK: - Voice Agent Settings

enum VoiceAgentVoice: String, CaseIterable, Identifiable {
    case marin, cedar, alloy, ash, ballad, coral, echo, sage, shimmer, verse
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum VoiceAgentModel: String, CaseIterable, Identifiable {
    case realtime = "gpt-realtime-1.5"
    var id: String { rawValue }
    var displayName: String { "GPT Realtime 1.5" }
}

struct SettingsView: View {
    @EnvironmentObject private var configManager: AppConfigManager
    @EnvironmentObject private var audioManager: AudioManager
    @EnvironmentObject private var updateManager: UpdateManager
    @ObservedObject private var cliInstaller = CLIInstaller.shared
    @State private var apiKey: String = ""
    @State private var apiKeyError: String?
    @FocusState private var isAPIKeyFieldFocused: Bool

    @AppStorage("voiceAgentVoice") private var selectedVoice: VoiceAgentVoice = .marin
    @AppStorage("voiceAgentModel") private var selectedModel: VoiceAgentModel = .realtime
    @AppStorage("safeModeEnabled") private var safeModeEnabled = false
    @AppStorage("autoAbortOnBargeIn") private var autoAbortOnBargeIn = true

    var body: some View {
        Form {
            Section {
                SecureField("", text: $apiKey, prompt: Text("sk-..."))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .labelsHidden()
                    .focused($isAPIKeyFieldFocused)
                    .onSubmit { persistAPIKeyIfNeeded() }
                    .onChange(of: apiKey) { _, _ in
                        apiKeyError = nil
                    }
                    .onChange(of: isAPIKeyFieldFocused) { oldValue, newValue in
                        if oldValue && !newValue { persistAPIKeyIfNeeded() }
                    }

                HStack {
                    Text("Stored securely in macOS Keychain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link("Get API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
                }

                if let apiKeyError {
                    Text(apiKeyError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("OpenAI API Key")
            }

            Section("Voice Agent") {
                Picker("Voice", selection: $selectedVoice) {
                    ForEach(VoiceAgentVoice.allCases) { voice in
                        Text(voice.displayName).tag(voice)
                    }
                }

                Picker("Model", selection: $selectedModel) {
                    ForEach(VoiceAgentModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }

                Toggle("Safe mode", isOn: $safeModeEnabled)
                Text("Disable write/edit tools and restrict shell commands to a safe allowlist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-abort on barge-in", isOn: $autoAbortOnBargeIn)
                Text("When enabled, interrupting speech truncates the current assistant response.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                LaunchAtLogin.Toggle("Launch at login")

                HStack {
                    Text("Activate")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .toggleRecording)
                }

                HStack {
                    Text("Open Settings")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .openSettings)
                }

                Text("If the menu bar icon is hidden, use this shortcut to reopen Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Text("Microphone")
                    Spacer()
                    if audioManager.microphonePermissionState == .granted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    } else {
                        Button(microphoneActionLabel) {
                            handleMicrophoneAction()
                        }
                    }
                }
            }

            Section("CLI Tools") {
                HStack {
                    cliStatusLabel
                    Spacer()
                    Button(cliInstaller.isInstalled ? "Reinstall" : "Download") {
                        Task { await cliInstaller.install() }
                    }
                    .disabled({
                        if case .downloading = cliInstaller.status { return true }
                        return false
                    }())
                }
                if cliInstaller.isInstalled {
                    Button("Uninstall", role: .destructive) {
                        cliInstaller.uninstall()
                    }
                }
                Text("Downloads `rubber-duck` to ~/Library/Application Support and symlinks to /usr/local/bin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                HStack {
                    Button("Check for Updates...") {
                        updateManager.checkForUpdates()
                    }
                    .disabled(!updateManager.canCheckForUpdates)

                    Spacer()

                    Link("Release Notes", destination: URL(string: "https://github.com/mblode/rubber-duck/releases")!)
                        .font(.callout)
                }

                Toggle("Automatically check for updates", isOn: automaticallyChecksBinding)

                Toggle("Automatically download updates", isOn: automaticallyDownloadsBinding)
                    .disabled(!updateManager.automaticallyChecksForUpdates)

                Text("Updates are checked against signed, notarized GitHub releases.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Show Logs") {
                        Logger.shared.openLogFile()
                    }
                    Spacer()
                    Link("GitHub", destination: URL(string: "https://github.com/mblode/rubber-duck")!)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 430, height: 500)
        .onAppear {
            apiKey = configManager.getAPIKey() ?? ""
            apiKeyError = nil
            audioManager.refreshMicrophonePermissionState()
        }
        .onDisappear {
            persistAPIKeyIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            audioManager.refreshMicrophonePermissionState()
        }
    }

    private var microphoneActionLabel: String {
        switch audioManager.microphonePermissionState {
        case .granted: return "Granted"
        case .notDetermined: return "Allow"
        case .denied, .restricted: return "Open Settings"
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

    @ViewBuilder
    private var cliStatusLabel: some View {
        switch cliInstaller.status {
        case .notInstalled:
            Label("rubber-duck not installed", systemImage: "terminal")
        case .downloading:
            Label("Downloading rubber-duck...", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .installed(let v):
            Label("rubber-duck v\(v) installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .updateAvailable(let installed, let new):
            Label("Update available: v\(installed) → v\(new)", systemImage: "arrow.up.circle")
                .foregroundStyle(.orange)
        case .error(let msg):
            Text(msg).foregroundStyle(.red)
        }
    }

    private func persistAPIKeyIfNeeded() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingKey = configManager.getAPIKey() ?? ""
        guard trimmedKey != existingKey else { return }
        let didPersist = configManager.setAPIKey(trimmedKey)
        if didPersist {
            apiKey = trimmedKey
            apiKeyError = nil
        } else {
            apiKeyError = "Couldn't save API key to Keychain. Check RubberDuck.log for details."
        }
    }

    private var automaticallyChecksBinding: Binding<Bool> {
        Binding(
            get: { updateManager.automaticallyChecksForUpdates },
            set: { updateManager.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var automaticallyDownloadsBinding: Binding<Bool> {
        Binding(
            get: { updateManager.automaticallyDownloadsUpdates },
            set: { updateManager.setAutomaticallyDownloadsUpdates($0) }
        )
    }
}
