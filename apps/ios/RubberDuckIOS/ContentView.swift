import RubberDuckRemoteCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: RemoteDaemonAppModel
    @EnvironmentObject private var voiceModel: RemoteIOSVoiceSessionModel
    @State private var isShowingPairingSheet = false

    var body: some View {
        Group {
            if !appModel.isBootstrapped {
                bootingView
            } else if appModel.hasPairedHosts {
                TabView {
                    Tab("Voice", systemImage: "mic.fill") {
                        VoiceTab(isShowingPairingSheet: $isShowingPairingSheet)
                    }

                    Tab("Sessions", systemImage: "folder") {
                        SessionsTab()
                    }

                    Tab("Settings", systemImage: "gearshape") {
                        SettingsTab(isShowingPairingSheet: $isShowingPairingSheet)
                    }
                }
                .tint(Theme.accent)
            } else {
                EmptyStateView(
                    icon: "desktopcomputer",
                    title: "Rubber Duck Remote",
                    subtitle: "Pair this phone with your Mac to start voice coding against a live repo.",
                    actionTitle: "Pair a Mac",
                    action: { isShowingPairingSheet = true }
                )
            }
        }
        .task {
            if !appModel.isBootstrapped {
                await appModel.boot()
            }
        }
        .sheet(isPresented: $isShowingPairingSheet) {
            PairingSheet(isPresented: $isShowingPairingSheet)
                .environmentObject(appModel)
                .environmentObject(voiceModel)
        }
        .alert(
            "Rubber Duck Remote",
            isPresented: Binding(
                get: { appModel.lastError != nil || voiceModel.lastError != nil },
                set: { if !$0 { appModel.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                appModel.dismissError()
                voiceModel.clearError()
            }
        } message: {
            Text(appModel.lastError ?? voiceModel.lastError ?? "")
        }
    }

    private var bootingView: some View {
        VStack(spacing: Theme.spacing16) {
            ProgressView()
            Text("Loading...")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .environmentObject(RemoteDaemonAppModel(transport: MockRemoteDaemonTransport()))
        .environmentObject(RemoteIOSVoiceSessionModel())
}
