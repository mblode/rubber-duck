import RubberDuckRemoteCore
import SwiftUI

struct SettingsTab: View {
    @EnvironmentObject private var appModel: RemoteDaemonAppModel
    @EnvironmentObject private var voiceModel: RemoteIOSVoiceSessionModel
    @Binding var isShowingPairingSheet: Bool

    @State private var apiKeyDraft = ""
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                pairedMacsSection
                voiceSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            if apiKeyDraft.isEmpty {
                apiKeyDraft = RemoteOpenAIKeychainStore().loadAPIKey() ?? ""
            }
        }
    }

    // MARK: - Paired Macs

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Remote") {
                StatusIndicator.connectionStatus(appModel.connectionState)
            }

            LabeledContent("Voice") {
                Label(
                    voiceModel.hasAPIKey ? "Configured" : "Needs API Key",
                    systemImage: voiceModel.hasAPIKey ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                )
                .font(.footnote.weight(.medium))
                .foregroundStyle(voiceModel.hasAPIKey ? Theme.statusGreen : Theme.statusOrange)
            }

            if let activeHost = appModel.activeHost {
                LabeledContent("Selected Mac", value: activeHost.displayName)
            }
        }
    }

    private var pairedMacsSection: some View {
        Section {
            ForEach(appModel.pairingSnapshot.hosts) { host in
                Button {
                    Task { await appModel.selectHost(host) }
                } label: {
                    HostRow(
                        host: host,
                        isSelected: host.id == appModel.activeHost?.id
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                isShowingPairingSheet = true
            } label: {
                Label("Pair a Mac", systemImage: "plus.circle")
            }
        } header: {
            Text("Paired Macs")
        } footer: {
            Text("Choose which Mac receives session refreshes and tool calls from this iPhone.")
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section {
            SecureField("sk-...", text: $apiKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .privacySensitive()
                .onChange(of: apiKeyDraft) { _, _ in
                    saveError = nil
                }

            HStack {
                Label(
                    voiceModel.hasAPIKey ? "API key saved" : "API key missing",
                    systemImage: voiceModel.hasAPIKey ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(voiceModel.hasAPIKey ? Theme.statusGreen : Theme.statusOrange)
                .font(.footnote)

                Spacer()

                Button("Save Key") {
                    do {
                        try voiceModel.saveAPIKey(apiKeyDraft)
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let saveError {
                Label(saveError, systemImage: "xmark.circle.fill")
                    .foregroundStyle(Theme.statusRed)
                    .font(.footnote)
            }

            if voiceModel.hasAPIKey {
                Button("Remove API Key", role: .destructive) {
                    do {
                        try voiceModel.deleteAPIKey()
                        apiKeyDraft = ""
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
            }
        } header: {
            Text("OpenAI Realtime")
        } footer: {
            Text("Voice runs directly from this iPhone to OpenAI. The key is stored in iOS Keychain and never sent to your Mac.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–")
        }
    }
}
