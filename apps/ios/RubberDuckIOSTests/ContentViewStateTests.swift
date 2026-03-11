import RubberDuckRemoteCore
import Testing
@testable import RubberDuckIOS

@Suite("ContentView state routing")
@MainActor
struct ContentViewStateTests {
    @Test("App model starts not bootstrapped")
    func initialNotBootstrapped() {
        let model = TestFixtures.makeAppModel()
        #expect(!model.isBootstrapped)
    }

    @Test("App model boots to bootstrapped state")
    func bootsSuccessfully() async {
        let model = TestFixtures.makeAppModel()
        await model.boot()
        #expect(model.isBootstrapped)
    }

    @Test("No paired hosts when pairing store is empty")
    func noPairedHosts() async {
        let model = TestFixtures.makeAppModel()
        await model.boot()
        #expect(!model.hasPairedHosts)
    }

    @Test("Dismiss error clears lastError")
    func dismissErrorClears() {
        let model = TestFixtures.makeAppModel()
        model.lastError = "Test error"
        model.dismissError()
        #expect(model.lastError == nil)
    }

    @Test("Voice model starts with idle state")
    func voiceModelInitialState() {
        let model = RemoteIOSVoiceSessionModel()
        #expect(model.voiceState == .idle)
        #expect(!model.isPressingToTalk)
        #expect(!model.isPreparing)
    }
}
