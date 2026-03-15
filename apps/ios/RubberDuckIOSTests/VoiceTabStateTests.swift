import RubberDuckRemoteCore
import Testing
@testable import RubberDuckIOS

@Suite("VoiceTab computed state")
struct VoiceTabStateTests {
    @Test("TalkButton label for idle state")
    func talkButtonLabelIdle() {
        let button = TalkButton(
            isEnabled: true,
            voiceState: .idle,
            isPreparing: false,
            isPressingToTalk: false,
            onPressStart: {},
            onPressEnd: {}
        )
        #expect(button.buttonLabel == "Talk")
    }

    @Test("TalkButton label for listening state")
    func talkButtonLabelListening() {
        let button = TalkButton(
            isEnabled: true,
            voiceState: .listening,
            isPreparing: false,
            isPressingToTalk: true,
            onPressStart: {},
            onPressEnd: {}
        )
        #expect(button.buttonLabel == "Listening")
    }

    @Test("TalkButton label for thinking state")
    func talkButtonLabelThinking() {
        let button = TalkButton(
            isEnabled: true,
            voiceState: .thinking,
            isPreparing: false,
            isPressingToTalk: false,
            onPressStart: {},
            onPressEnd: {}
        )
        #expect(button.buttonLabel == "Thinking")
    }

    @Test("TalkButton label for speaking state")
    func talkButtonLabelSpeaking() {
        let button = TalkButton(
            isEnabled: true,
            voiceState: .speaking,
            isPreparing: false,
            isPressingToTalk: false,
            onPressStart: {},
            onPressEnd: {}
        )
        #expect(button.buttonLabel == "Speaking")
    }

    @Test("TalkButton label for toolRunning state")
    func talkButtonLabelTool() {
        let button = TalkButton(
            isEnabled: true,
            voiceState: .toolRunning,
            isPreparing: false,
            isPressingToTalk: false,
            onPressStart: {},
            onPressEnd: {}
        )
        #expect(button.buttonLabel == "Working")
    }

    @Test("TalkButton label for preparing state")
    func talkButtonLabelPreparing() {
        let button = TalkButton(
            isEnabled: true,
            voiceState: .idle,
            isPreparing: true,
            isPressingToTalk: false,
            onPressStart: {},
            onPressEnd: {}
        )
        #expect(button.buttonLabel == "Connecting")
    }

    @Test("TalkButton icon when not pressing")
    func talkButtonIconIdle() {
        let button = TalkButton(
            isEnabled: true,
            voiceState: .idle,
            isPreparing: false,
            isPressingToTalk: false,
            onPressStart: {},
            onPressEnd: {}
        )
        #expect(button.iconName == "mic.fill")
    }

    @Test("TalkButton icon when pressing")
    func talkButtonIconPressing() {
        let button = TalkButton(
            isEnabled: true,
            voiceState: .listening,
            isPreparing: false,
            isPressingToTalk: true,
            onPressStart: {},
            onPressEnd: {}
        )
        #expect(button.iconName == "waveform")
    }
}
