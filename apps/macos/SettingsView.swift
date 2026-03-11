import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin
import AppKit
import CoreImage.CIFilterBuiltins

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
    @StateObject private var remotePairingController = RemotePairingController()
    @State private var apiKey: String = ""
    @State private var apiKeyError: String?
    @FocusState private var isAPIKeyFieldFocused: Bool

    @AppStorage("voiceAgentVoice") private var selectedVoice: VoiceAgentVoice = .marin
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

                Toggle("Safe mode", isOn: $safeModeEnabled)
                Text("Disable write/edit tools and restrict shell commands to a safe allowlist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-abort on barge-in", isOn: $autoAbortOnBargeIn)
                Text("When enabled, speaking over the assistant interrupts the current response.")
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
                cliToolsSection
            }

            Section("iPhone Pairing") {
                remotePairingSection
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
            Task {
                await remotePairingController.loadStatus()
            }
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
    private var cliToolsSection: some View {
        switch cliInstaller.status {
        case .notInstalled:
            HStack {
                Label("duck not installed", systemImage: "terminal")
                Spacer()
                Button("Download") { Task { await cliInstaller.install() } }
            }
            Text("Downloads `duck` to ~/Library/Application Support and symlinks to /usr/local/bin")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .downloading:
            Label("Downloading duck...", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)

        case .installed(let v):
            HStack {
                Label("duck v\(v) – /usr/local/bin/duck", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Reinstall") { Task { await cliInstaller.install() } }
            }
            Button("Uninstall", role: .destructive) { cliInstaller.uninstall() }

        case .updateAvailable(let installed, let new):
            HStack {
                Label("Update: v\(installed) → v\(new)", systemImage: "arrow.up.circle")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Update") { Task { await cliInstaller.install() } }
            }

        case .error(let msg):
            HStack {
                Label(msg, systemImage: "xmark.circle").foregroundStyle(.red)
                Spacer()
                Button("Retry") { Task { await cliInstaller.install() } }
            }

        case .symlinkError(let info):
            cliSymlinkErrorSection(info)
        }
    }

    @ViewBuilder
    private var remotePairingSection: some View {
        if let pairingLink = remotePairingController.pairingLink {
            VStack(spacing: 12) {
                if let qrImage = qrImage(for: pairingLink) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 160, height: 160)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        )
                }

                HStack(spacing: 8) {
                    Button("Copy Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(pairingLink, forType: .string)
                    }
                    Button("Regenerate") {
                        Task { await remotePairingController.preparePairing() }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            Button(remotePairingController.isLoading ? "Preparing..." : "Generate QR Code") {
                Task { await remotePairingController.preparePairing() }
            }
            .disabled(remotePairingController.isLoading)
        }

        Text("Scan this QR code with the iPhone app. Or run `duck remote pair` in the terminal.")
            .font(.caption)
            .foregroundStyle(.secondary)

        if let error = remotePairingController.errorMessage ?? remotePairingController.status?.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func qrImage(for string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "Q"

        guard let outputImage = filter.outputImage?.transformed(
            by: CGAffineTransform(scaleX: 10, y: 10)
        ) else {
            return nil
        }

        let imageRep = NSCIImageRep(ciImage: outputImage)
        let image = NSImage(size: imageRep.size)
        image.addRepresentation(imageRep)
        return image
    }

    @ViewBuilder
    private func cliSymlinkErrorSection(_ info: SymlinkErrorInfo) -> some View {
        switch info.kind {
        case .localBinInstalled:
            HStack {
                Label("duck installed to ~/.local/bin", systemImage: "checkmark.circle")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Reinstall") { Task { await cliInstaller.install() } }
            }
            Button("Uninstall", role: .destructive) { cliInstaller.uninstall() }
            if info.localBinInPath {
                Text("Run `duck` in your terminal. ~/.local/bin is on your PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add ~/.local/bin to your PATH:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(#"export PATH="$HOME/.local/bin:$PATH""#)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                #"export PATH="$HOME/.local/bin:$PATH""#,
                                forType: .string
                            )
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy to clipboard")
                    }
                }
            }

        case .userCancelled:
            HStack {
                Label("Admin access declined", systemImage: "lock.slash")
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button("Try Again") { Task { await cliInstaller.install() } }
                Button("Use ~/.local/bin") { Task { await cliInstaller.installToLocalBin() } }
            }
            Text("/usr/local/bin requires admin rights. ~/.local/bin needs no password.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .permissionDenied:
            HStack {
                Label("Symlink failed", systemImage: "xmark.circle").foregroundStyle(.red)
                Spacer()
                Button("Retry") { Task { await cliInstaller.install() } }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Run in Terminal to finish setup:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let cmd = "sudo ln -sfn '\(info.binaryPath)' /usr/local/bin/duck"
                HStack {
                    Text(cmd)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy command")
                }
            }
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
