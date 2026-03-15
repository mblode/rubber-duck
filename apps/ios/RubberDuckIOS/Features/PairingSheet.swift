import RubberDuckRemoteCore
import SwiftUI

struct PairingSheet: View {
    let configuration: AppRuntimeConfiguration
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: RemoteDaemonAppModel
    @EnvironmentObject private var voiceModel: RemoteIOSVoiceSessionModel
    @Binding var isPresented: Bool

    @State private var displayName = ""
    @State private var hostURLString = ""
    @State private var authToken = ""
    @State private var openAIKey = ""
    @State private var isShowingQRScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: Theme.spacing12) {
                        Text("Connect this iPhone to your Mac")
                            .font(.headline)

                        Text("Scan the pairing QR on your Mac, or enter the host and access token below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            isShowingQRScanner = true
                        } label: {
                            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("pairing-scan-button")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding(.vertical, Theme.spacing4)
                }

                Section("Connection") {
                    TextField("Display name", text: $displayName)
                        .textContentType(.nickname)
                        .accessibilityIdentifier("pairing-display-name-field")

                    TextField("linktree, 100.96.185.34, or full URL", text: $hostURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .accessibilityIdentifier("pairing-host-field")
                }

                Section("Authentication") {
                    SecureField("Paste the daemon token", text: $authToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .privacySensitive()
                        .accessibilityIdentifier("pairing-token-field")

                    Text("Use the token from `duck remote enable` or the Mac pairing flow. Stored securely in iOS Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Voice") {
                    SecureField("sk-...", text: $openAIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .privacySensitive()
                        .accessibilityIdentifier("pairing-openai-key-field")

                    Text("Used only on this iPhone for direct Realtime voice. Stored in iOS Keychain, never sent to your Mac.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("After pairing") {
                    Label("App reopens on the current repo by default.", systemImage: "arrow.trianglehead.clockwise")
                    Label("Voice goes from iPhone straight to OpenAI Realtime.", systemImage: "waveform")
                    Label("Tool calls run on your Mac against the live workspace.", systemImage: "desktopcomputer")
                }
                .font(.footnote)
            }
            .navigationTitle("Pair a Mac")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(isSaving)
            .task {
                if openAIKey.isEmpty {
                    openAIKey = configuration.makeOpenAIKeyStore().loadAPIKey() ?? ""
                }

                if let pairingSeed = configuration.pairingSeed {
                    if displayName.isEmpty {
                        displayName = pairingSeed.displayName
                    }
                    if hostURLString.isEmpty {
                        hostURLString = pairingSeed.hostURLString
                    }
                    if authToken.isEmpty {
                        authToken = pairingSeed.authToken
                    }
                }

                if openAIKey.isEmpty,
                   let configuredOpenAIKey = configuration.openAIKey {
                    openAIKey = configuredOpenAIKey
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismissSheet() }
                        .accessibilityIdentifier("pairing-close-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await savePairing()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Pair")
                        }
                    }
                    .accessibilityIdentifier("pairing-save-button")
                    .disabled(!canSave)
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingQRScanner) {
            QRScannerSheet(isPresented: $isShowingQRScanner) { scannedCode in
                applyScannedCode(scannedCode)
            }
        }
    }

    private func dismissSheet() {
        isPresented = false
        dismiss()
    }

    private func applyScannedCode(_ scannedCode: String) {
        do {
            let payload = try PairingPayload.parse(scannedCode)
            hostURLString = payload.host
            authToken = payload.token
            if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                displayName = payload.displayName ?? ""
            }
            appModel.lastError = nil
        } catch {
            appModel.lastError = error.localizedDescription
        }
    }

    private var isSaving: Bool {
        appModel.connectionState == .pairing || appModel.connectionState == .connecting
    }

    private var canSave: Bool {
        !hostURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !authToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSaving
    }

    @MainActor
    private func savePairing() async {
        await appModel.pair(
            hostURLString: hostURLString,
            displayName: displayName,
            authToken: authToken
        )

        if appModel.lastError == nil {
            if !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    try voiceModel.saveAPIKey(openAIKey)
                } catch {
                    appModel.lastError = error.localizedDescription
                    return
                }
            }

            dismissSheet()
        }
    }
}
