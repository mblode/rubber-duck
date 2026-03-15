import RubberDuckRemoteCore
import SwiftUI

@main
struct RubberDuckIOSApp: App {
    private let configuration: AppRuntimeConfiguration
    @StateObject private var appModel: RemoteDaemonAppModel
    @StateObject private var voiceModel: RemoteIOSVoiceSessionModel

    init() {
        let configuration = AppRuntimeConfiguration()

        if configuration.resetStateOnLaunch {
            configuration.resetPersistedState()
        }

        configuration.seedLaunchStateIfNeeded()

        let appModel = RemoteDaemonAppModel(
            transport: configuration.makeTransport(),
            pairingStore: configuration.makePairingStore()
        )
        let voiceModel = configuration.makeVoiceModel()

        self.configuration = configuration
        _appModel = StateObject(
            wrappedValue: appModel
        )
        _voiceModel = StateObject(wrappedValue: voiceModel)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(configuration: configuration)
                .tint(Theme.accent)
                .environmentObject(appModel)
                .environmentObject(voiceModel)
        }
    }
}
