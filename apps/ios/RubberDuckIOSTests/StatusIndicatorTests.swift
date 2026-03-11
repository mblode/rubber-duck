import RubberDuckRemoteCore
import Testing
@testable import RubberDuckIOS

@Suite("StatusIndicator mapping")
struct StatusIndicatorTests {
    @Test("Connection state labels")
    func connectionLabels() {
        #expect(StatusIndicator.statusLabel(for: .idle) == "Idle")
        #expect(StatusIndicator.statusLabel(for: .pairing) == "Pairing")
        #expect(StatusIndicator.statusLabel(for: .connecting) == "Connecting")
        #expect(StatusIndicator.statusLabel(for: .connected) == "Connected")
        #expect(StatusIndicator.statusLabel(for: .failed) == "Failed")
    }

    @Test("Voice state labels")
    func voiceLabels() {
        #expect(StatusIndicator.voiceLabel(for: .idle) == "Ready")
        #expect(StatusIndicator.voiceLabel(for: .connecting) == "Connecting")
        #expect(StatusIndicator.voiceLabel(for: .listening) == "Listening")
        #expect(StatusIndicator.voiceLabel(for: .thinking) == "Thinking")
        #expect(StatusIndicator.voiceLabel(for: .speaking) == "Speaking")
        #expect(StatusIndicator.voiceLabel(for: .toolRunning) == "Running tool")
    }
}
