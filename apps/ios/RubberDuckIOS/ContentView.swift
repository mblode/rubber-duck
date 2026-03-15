import RubberDuckRemoteCore
import SwiftUI

struct ContentView: View {
    let configuration: AppRuntimeConfiguration
    @EnvironmentObject private var appModel: RemoteDaemonAppModel
    @EnvironmentObject private var voiceModel: RemoteIOSVoiceSessionModel
    @State private var isShowingPairingSheet = false
    @State private var hasAppliedLaunchConfiguration = false

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
                NavigationStack {
                    EmptyStateView(
                        icon: "desktopcomputer",
                        title: "Rubber Duck Remote",
                        subtitle: "Pair this phone with your Mac to start voice coding against a live repo.",
                        actionTitle: "Pair a Mac",
                        action: { isShowingPairingSheet = true }
                    )
                    .navigationTitle("Rubber Duck Remote")
                    .navigationBarTitleDisplayMode(.large)
                }
            }
        }
        .task {
            if !appModel.isBootstrapped {
                await appModel.boot()
            }
        }
        .task(id: appModel.isBootstrapped) {
            guard appModel.isBootstrapped else {
                return
            }

            await applyLaunchConfigurationIfNeeded()
        }
        .sheet(isPresented: $isShowingPairingSheet) {
            PairingSheet(configuration: configuration, isPresented: $isShowingPairingSheet)
                .environmentObject(appModel)
                .environmentObject(voiceModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
        ProgressView("Loading")
            .controlSize(.large)
            .font(.footnote)
            .foregroundStyle(Theme.secondaryLabel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.groupedBackground)
    }

    @MainActor
    private func applyLaunchConfigurationIfNeeded() async {
        guard !hasAppliedLaunchConfiguration else {
            return
        }

        hasAppliedLaunchConfiguration = true
        guard configuration.autoPairOnLaunch,
              !appModel.hasPairedHosts,
              let pairingSeed = configuration.pairingSeed else {
            return
        }

        await appModel.pair(
            hostURLString: pairingSeed.hostURLString,
            displayName: pairingSeed.displayName,
            authToken: pairingSeed.authToken
        )

        if appModel.lastError == nil,
           let openAIKey = configuration.openAIKey {
            try? voiceModel.saveAPIKey(openAIKey)
        }

        if appModel.lastError != nil {
            isShowingPairingSheet = true
        }
    }
}

#Preview {
    ContentView(configuration: AppRuntimeConfiguration())
        .environmentObject(RemoteDaemonAppModel(transport: MockRemoteDaemonTransport()))
        .environmentObject(RemoteIOSVoiceSessionModel())
}
