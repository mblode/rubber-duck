import RubberDuckRemoteCore
import SwiftUI

struct PairingSheet: View {
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
                    VStack(alignment: .leading, spacing: Theme.spacing8) {
                        Text("Connect this phone to your Mac")
                            .font(.headline)

                        Text("Open the remote pairing screen on your Mac, then scan its QR code or enter the host and token below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            isShowingQRScanner = true
                        } label: {
                            Label("Scan QR from Mac", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                    .padding(.vertical, Theme.spacing4)
                }

                Section("Mac") {
                    TextField("Display name", text: $displayName)
                    TextField("linktree, 100.96.185.34, or full URL", text: $hostURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                Section("Access Token") {
                    TextField("Paste the daemon token", text: $authToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)

                    Text("Use the token from `duck remote enable` or the Mac pairing flow. Stored securely in iOS Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("OpenAI") {
                    SecureField("sk-...", text: $openAIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

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
            .task {
                if openAIKey.isEmpty {
                    openAIKey = RemoteOpenAIKeychainStore().loadAPIKey() ?? ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismissSheet() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
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
                    .disabled(appModel.connectionState == .pairing || appModel.connectionState == .connecting)
                }
            }
        }
        .sheet(isPresented: $isShowingQRScanner) {
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
}
