import RubberDuckRemoteCore
import SwiftUI

struct SettingsTab: View {
    @EnvironmentObject private var appModel: RemoteDaemonAppModel
    @EnvironmentObject private var voiceModel: RemoteIOSVoiceSessionModel
    @Binding var isShowingPairingSheet: Bool

    @State private var apiKeyDraft = ""
    @State private var saveError: String?

    var body: some View {
        Form {
            pairedMacsSection
            voiceSection
            aboutSection
        }
        .task {
            if apiKeyDraft.isEmpty {
                apiKeyDraft = RemoteOpenAIKeychainStore().loadAPIKey() ?? ""
            }
        }
    }

    // MARK: - Paired Macs

    private var pairedMacsSection: some View {
        Section("Paired Macs") {
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
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section {
            SecureField("sk-...", text: $apiKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
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

                Button("Save") {
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
