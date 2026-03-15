import RubberDuckRemoteCore
import SwiftUI

struct VoiceTab: View {
    @EnvironmentObject private var appModel: RemoteDaemonAppModel
    @EnvironmentObject private var voiceModel: RemoteIOSVoiceSessionModel
    @Binding var isShowingPairingSheet: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section("Current Setup") {
                        sessionOverview
                    }

                    Section {
                        talkSection
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.spacing8)
                            .listRowSeparator(.hidden)
                    } footer: {
                        Text(talkSubtitle)
                    }

                    Section("Conversation") {
                        if appModel.activeSession == nil {
                            transcriptEmptyState(
                                icon: "rectangle.stack",
                                title: "Select a Session",
                                subtitle: "Open the Sessions tab to choose the workspace you want to control from this iPhone."
                            )
                        } else if voiceModel.liveConversation.isEmpty {
                            transcriptEmptyState(
                                icon: "text.bubble",
                                title: "No Transcript Yet",
                                subtitle: "Hold the talk button or send a typed prompt to start."
                            )
                        } else {
                            ForEach(voiceModel.liveConversation) { entry in
                                MessageRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Voice")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await appModel.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
                .refreshable {
                    await appModel.refresh()
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
                .onChange(of: voiceModel.liveConversation.count) { _, _ in
                    guard let lastID = voiceModel.liveConversation.last?.id else { return }

                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var sessionOverview: some View {
        VStack(alignment: .leading, spacing: Theme.spacing12) {
            HStack(alignment: .top, spacing: Theme.spacing12) {
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    Label(appModel.selectedHostName, systemImage: "desktopcomputer")
                        .font(.headline)
                        .foregroundStyle(Theme.label)

                    if let session = appModel.activeSession {
                        Text(session.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.label)

                        Text(session.workspacePath)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryLabel)
                            .lineLimit(2)
                    } else {
                        Text("No workspace selected")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }

                Spacer()

                StatusIndicator.connectionStatus(appModel.connectionState)
            }

            HStack(spacing: Theme.spacing8) {
                StatusIndicator.voiceStatus(voiceModel.voiceState)

                if let lastSyncedAt = appModel.lastSyncedAt {
                    Text("Last synced \(lastSyncedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryLabel)
                }

                Spacer()

                if !voiceModel.hasAPIKey {
                    Label("API key required", systemImage: "key.horizontal.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .padding(.vertical, Theme.spacing4)
    }

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
        }
    }

    @ViewBuilder
    private func transcriptEmptyState(icon: String, title: String, subtitle: String) -> some View {
        EmptyStateView(
            icon: icon,
            title: title,
            subtitle: subtitle
        )
        .frame(maxWidth: .infinity, minHeight: 240)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .padding(.vertical, Theme.spacing8)
    }

    private var talkEnabled: Bool {
        appModel.activeSession != nil
    }

    private var talkSubtitle: String {
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
