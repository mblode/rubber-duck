import RubberDuckRemoteCore
import SwiftUI

struct StatusIndicator: View {
    let label: String
    let color: Color
    let systemImage: String

    var body: some View {
        Label {
            Text(label)
                .font(.caption.weight(.semibold))
        } icon: {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(color)
        .padding(.horizontal, Theme.spacing8)
        .padding(.vertical, Theme.spacing4)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.14))
        )
    }
}

extension StatusIndicator {
    static func connectionStatus(_ state: RemoteConnectionState) -> StatusIndicator {
        StatusIndicator(
            label: statusLabel(for: state),
            color: statusColor(for: state),
            systemImage: statusImage(for: state)
        )
    }

    static func voiceStatus(_ state: RemoteDaemonVoiceState) -> StatusIndicator {
        StatusIndicator(
            label: voiceLabel(for: state),
            color: voiceColor(for: state),
            systemImage: voiceImage(for: state)
        )
    }

    static func statusLabel(for state: RemoteConnectionState) -> String {
        switch state {
        case .idle: "Idle"
        case .pairing: "Pairing"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .failed: "Failed"
        }
    }

    static func statusColor(for state: RemoteConnectionState) -> Color {
        switch state {
        case .idle: Theme.secondaryLabel
        case .pairing: Theme.statusOrange
        case .connecting: Color(.systemBlue)
        case .connected: Theme.statusGreen
        case .failed: Theme.statusRed
        }
    }

    static func statusImage(for state: RemoteConnectionState) -> String {
        switch state {
        case .idle: "pause.circle.fill"
        case .pairing: "link.badge.plus"
        case .connecting: "arrow.trianglehead.clockwise"
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    static func voiceLabel(for state: RemoteDaemonVoiceState) -> String {
        switch state {
        case .idle: "Ready"
        case .connecting: "Connecting"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .toolRunning: "Running tool"
        }
    }

    static func voiceColor(for state: RemoteDaemonVoiceState) -> Color {
        switch state {
        case .idle: Theme.secondaryLabel
        case .connecting: Color(.systemBlue)
        case .listening: Theme.statusGreen
        case .thinking: Theme.statusOrange
        case .speaking: Theme.accent
        case .toolRunning: Color(.systemBlue)
        }
    }

    static func voiceImage(for state: RemoteDaemonVoiceState) -> String {
        switch state {
        case .idle: "waveform.badge.mic"
        case .connecting: "bolt.horizontal.circle.fill"
        case .listening: "waveform"
        case .thinking: "sparkles"
        case .speaking: "speaker.wave.2.fill"
        case .toolRunning: "hammer.circle.fill"
        }
    }
}

struct StatusDot: View {
    let state: RemoteConnectionState

    var body: some View {
        Circle()
            .fill(StatusIndicator.statusColor(for: state))
            .frame(width: 10, height: 10)
            .accessibilityLabel(StatusIndicator.statusLabel(for: state))
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusIndicator.connectionStatus(.connected)
        StatusIndicator.connectionStatus(.connecting)
        StatusIndicator.connectionStatus(.failed)
        StatusIndicator.voiceStatus(.listening)
        StatusIndicator.voiceStatus(.thinking)
        StatusDot(state: .connected)
        StatusDot(state: .failed)
    }
    .padding()
}
