import RubberDuckRemoteCore
import SwiftUI

struct VoiceTab: View {
    @EnvironmentObject private var appModel: RemoteDaemonAppModel
    @EnvironmentObject private var voiceModel: RemoteIOSVoiceSessionModel
    @Binding var isShowingPairingSheet: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: Theme.spacing16)
            talkSection
            Spacer(minLength: Theme.spacing16)
            transcript
        }
        .safeAreaInset(edge: .bottom) {
            ComposerBar(
                text: $appModel.draftMessage,
                isDisabled: appModel.activeSession == nil,
                onSend: {
                    Task { await appModel.sendDraft() }
                }
            )
        }
        .task(id: contextKey) {
            voiceModel.syncContext(
                host: appModel.activeHost,
                session: appModel.activeSession,
                seedConversation: appModel.conversation
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            HStack {
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    Text(appModel.selectedHostName)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.label)

                    if let session = appModel.activeSession {
                        Text(session.workspacePath)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryLabel)
                            .lineLimit(1)
                    }
                }

                Spacer()

                StatusIndicator.connectionStatus(appModel.connectionState)
            }

            HStack(spacing: Theme.spacing12) {
                StatusIndicator.voiceStatus(voiceModel.voiceState)

                if let lastSyncedAt = appModel.lastSyncedAt {
                    Text("Synced \(lastSyncedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryLabel)
                }

                Spacer()

                Button {
                    Task { await appModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.medium))
                }
                .tint(Theme.accent)
            }
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.top, Theme.spacing8)
    }

    // MARK: - Talk Section

    private var talkSection: some View {
        VStack(spacing: Theme.spacing12) {
            TalkButton(
                isEnabled: talkEnabled,
                voiceState: voiceModel.voiceState,
                isPreparing: voiceModel.isPreparing,
                isPressingToTalk: voiceModel.isPressingToTalk,
                onPressStart: {
                    if !voiceModel.hasAPIKey {
                        isShowingPairingSheet = true
                        return
                    }
                    Task { await voiceModel.beginPressToTalk() }
                },
                onPressEnd: {
                    Task { await voiceModel.endPressToTalk() }
                }
            )

            Text(talkSubtitle)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacing32)
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if voiceModel.liveConversation.isEmpty {
                        EmptyStateView(
                            icon: "text.bubble",
                            title: "No Transcript Yet",
                            subtitle: "Hold the talk button or send a typed prompt to start."
                        )
                    } else {
                        ForEach(voiceModel.liveConversation) { entry in
                            MessageRow(entry: entry)
                                .id(entry.id)
                                .padding(.horizontal, Theme.spacing16)
                        }
                    }
                }
            }
            .onChange(of: voiceModel.liveConversation.count) { _, _ in
                guard let lastID = voiceModel.liveConversation.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Computed State

    var talkEnabled: Bool {
        appModel.activeSession != nil && voiceModel.hasAPIKey
    }

    var talkSubtitle: String {
        if appModel.activeSession == nil {
            return "Select a session to start."
        }
        if !voiceModel.hasAPIKey {
            return "Add your OpenAI API key in Settings to enable voice."
        }
        if voiceModel.isPressingToTalk {
            return "Release to send."
        }
        return "Hold to talk."
    }

    private var contextKey: String {
        "\(appModel.activeHost?.id ?? "none")::\(appModel.activeSession?.id ?? "none")::\(appModel.conversation.count)"
    }
}
