import RubberDuckRemoteCore
import SwiftUI

@main
struct RubberDuckIOSApp: App {
    @StateObject private var appModel: RemoteDaemonAppModel
    @StateObject private var voiceModel = RemoteIOSVoiceSessionModel()

    init() {
        _appModel = StateObject(
            wrappedValue: RemoteDaemonAppModel(
                transport: RemoteDaemonTransportFactory.live()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(voiceModel)
        }
    }
}
