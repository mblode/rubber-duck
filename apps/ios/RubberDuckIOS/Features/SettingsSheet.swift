import RubberDuckRemoteCore
import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var appModel: RemoteDaemonAppModel
    @EnvironmentObject private var voiceModel: RemoteIOSVoiceSessionModel
    @Environment(\.dismiss) private var dismiss
    @Binding var isShowingPairingSheet: Bool

    @State private var apiKeyDraft = ""
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                if appModel.sessions.count > 1 {
                    sessionsSection
                }

                pairedMacsSection
                voiceSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            if apiKeyDraft.isEmpty {
                apiKeyDraft = RemoteOpenAIKeychainStore().loadAPIKey() ?? ""
            }
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        Section {
            ForEach(appModel.sessions) { session in
                Button {
                    Task {
                        await appModel.openSession(session)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: Theme.spacing12) {
                        Image(systemName: session.id == appModel.activeSession?.id ? "folder.fill" : "folder")
                            .font(.title3)
                            .foregroundStyle(session.id == appModel.activeSession?.id ? Theme.accent : Theme.secondaryLabel)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: Theme.spacing4) {
                            Text(session.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.label)

                            Text(session.workspacePath)
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        if session.id == appModel.activeSession?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Sessions")
        }
    }

    // MARK: - Paired Macs

    private var pairedMacsSection: some View {
        Section {
            ForEach(appModel.pairingSnapshot.hosts) { host in
                Button {
                    Task { await appModel.selectHost(host) }
                } label: {
                    HStack(spacing: Theme.spacing12) {
                        Image(systemName: host.id == appModel.activeHost?.id ? "desktopcomputer.circle.fill" : "desktopcomputer")
                            .font(.title2)
                            .foregroundStyle(host.id == appModel.activeHost?.id ? Theme.accent : Theme.secondaryLabel)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: Theme.spacing4) {
                            Text(host.displayName)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.label)

                            Text(host.subtitle)
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryLabel)
                        }

                        Spacer()

                        if host.id == appModel.activeHost?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                isShowingPairingSheet = true
                dismiss()
            } label: {
                Label("Pair a Mac", systemImage: "plus.circle")
            }
        } header: {
            Text("Paired Macs")
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
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
            LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-")
        }
    }
}
