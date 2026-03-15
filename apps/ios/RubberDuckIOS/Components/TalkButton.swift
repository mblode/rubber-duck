import RubberDuckRemoteCore
import SwiftUI

struct TalkButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .fill(fillColor.opacity(isPressingToTalk ? 0.14 : 0.08))
                .frame(width: 152, height: 152)
                .scaleEffect(haloScale)
                .animation(haloAnimation, value: isPressingToTalk)

            Circle()
                .fill(.regularMaterial)
                .overlay(
                    Circle()
                        .fill(fillColor.opacity(isPressingToTalk ? 0.95 : 0.14))
                )
                .frame(width: 112, height: 112)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isPressingToTalk ? 0.24 : 0.6), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(isPressingToTalk ? 0.18 : 0.1), radius: isPressed ? 4 : 12, y: isPressed ? 2 : 8)
                .scaleEffect(isPressed ? 0.94 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isPressed)

            VStack(spacing: Theme.spacing4) {
                Image(systemName: iconName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(isPressingToTalk ? Color.white : Theme.label)
                    .symbolEffect(.pulse, isActive: isPressingToTalk && !reduceMotion)

                Text(buttonLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPressingToTalk ? Color.white : Theme.secondaryLabel)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold to talk")
        .accessibilityHint("Press and hold to record your request, then release to send it.")
        .accessibilityValue(buttonLabel)
        .accessibilityAction(named: Text(isPressingToTalk ? "Stop recording" : "Start recording")) {
            guard isEnabled else { return }

            if isPressingToTalk {
                onPressEnd()
            } else {
                onPressStart()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: isPressed)
    }

    private var fillColor: Color {
        if isPressingToTalk {
            return Theme.accent
        }
        return Color(.tertiarySystemFill)
    }

    private var haloScale: CGFloat {
        guard isPressingToTalk, !reduceMotion else {
            return 1
        }

        return 1.06
    }

    private var haloAnimation: Animation? {
        guard !reduceMotion else {
            return .easeInOut(duration: 0.2)
        }

        return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    }

    var iconName: String {
        if isPressingToTalk || voiceState == .listening {
            return "waveform"
        }

        switch voiceState {
        case .idle, .connecting:
            return "mic.fill"
        case .thinking:
            return "sparkles"
        case .speaking:
            return "speaker.wave.2.fill"
        case .toolRunning:
            return "hammer.fill"
        case .listening:
            return "waveform"
        }
    }

    var buttonLabel: String {
        if isPreparing { return "Connecting" }
        switch voiceState {
        case .idle: return "Talk"
        case .connecting: return "Connecting"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        case .toolRunning: return "Working"
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
