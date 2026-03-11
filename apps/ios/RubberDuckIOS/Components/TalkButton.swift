import RubberDuckRemoteCore
import SwiftUI

struct TalkButton: View {
    let isEnabled: Bool
    let voiceState: RemoteDaemonVoiceState
    let isPreparing: Bool
    let isPressingToTalk: Bool
    let onPressStart: () -> Void
    let onPressEnd: () -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack {
            Circle()
                .fill(fillColor)
                .frame(width: 88, height: 88)
                .scaleEffect(isPressed ? 0.94 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isPressed)

            VStack(spacing: Theme.spacing4) {
                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)

                Text(buttonLabel)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed, isEnabled else { return }
                    isPressed = true
                    onPressStart()
                }
                .onEnded { _ in
                    guard isPressed else { return }
                    isPressed = false
                    onPressEnd()
                }
        )
        .opacity(isEnabled ? 1.0 : 0.4)
        .accessibilityLabel("Hold to talk")
        .accessibilityHint("Press and hold to record your request, then release to send it.")
        .sensoryFeedback(.impact(weight: .medium), trigger: isPressed)
    }

    private var fillColor: Color {
        if isPressingToTalk {
            return Theme.accent
        }
        return Color(.tertiarySystemFill)
    }

    var iconName: String {
        isPressingToTalk ? "waveform.circle.fill" : "mic.fill"
    }

    var buttonLabel: String {
        if isPreparing { return "Linking" }
        switch voiceState {
        case .idle, .listening: return "Hold"
        case .connecting: return "Linking"
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        case .toolRunning: return "Tool"
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        TalkButton(
            isEnabled: true,
            voiceState: .idle,
            isPreparing: false,
            isPressingToTalk: false,
            onPressStart: {},
            onPressEnd: {}
        )

        TalkButton(
            isEnabled: true,
            voiceState: .listening,
            isPreparing: false,
            isPressingToTalk: true,
            onPressStart: {},
            onPressEnd: {}
        )

        TalkButton(
            isEnabled: false,
            voiceState: .idle,
            isPreparing: false,
            isPressingToTalk: false,
            onPressStart: {},
            onPressEnd: {}
        )
    }
    .padding()
}
