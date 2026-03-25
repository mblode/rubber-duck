import RubberDuckRemoteCore
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appModel: RemoteDaemonAppModel
    @EnvironmentObject private var voiceModel: RemoteIOSVoiceSessionModel
    @Binding var isShowingPairingSheet: Bool

    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if voiceModel.liveConversation.isEmpty {
                        EmptyStateView(
                            icon: "text.bubble",
                            title: "No Transcript Yet",
                            subtitle: "Hold the talk button or send a typed prompt to start."
                        )
                        .frame(minHeight: 300)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(voiceModel.liveConversation) { entry in
                                MessageRow(entry: entry)
                                    .padding(.horizontal, Theme.spacing16)
                                    .padding(.vertical, 6)
                                    .id(entry.id)
                            }
                        }
                        .padding(.bottom, Theme.spacing8)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    bottomBar
                }
                .navigationTitle(appModel.activeSession?.name ?? "Rubber Duck")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        StatusDot(state: appModel.connectionState)
                    }
                }
                .refreshable {
                    await appModel.refresh()
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
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet(isShowingPairingSheet: $isShowingPairingSheet)
        }
        .accessibilityIdentifier("main-view")
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
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
            .padding(.top, Theme.spacing12)
            .padding(.bottom, Theme.spacing8)

            ComposerBar(
                text: $appModel.draftMessage,
                isDisabled: appModel.activeSession == nil,
                onSend: {
                    Task { await appModel.sendDraft() }
                }
            )
        }
        .background(.bar)
    }

    private var talkEnabled: Bool {
        appModel.activeSession != nil
    }

    private var contextKey: String {
        "\(appModel.activeHost?.id ?? "none")::\(appModel.activeSession?.id ?? "none")::\(appModel.conversation.count)"
    }
}
