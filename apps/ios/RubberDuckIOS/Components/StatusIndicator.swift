import RubberDuckRemoteCore
import SwiftUI

struct StatusIndicator: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: Theme.spacing4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}

extension StatusIndicator {
    static func connectionStatus(_ state: RemoteConnectionState) -> StatusIndicator {
        StatusIndicator(label: statusLabel(for: state), color: statusColor(for: state))
    }

    static func voiceStatus(_ state: RemoteDaemonVoiceState) -> StatusIndicator {
        StatusIndicator(label: voiceLabel(for: state), color: voiceColor(for: state))
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
}

#Preview {
    VStack(spacing: 12) {
        StatusIndicator.connectionStatus(.connected)
        StatusIndicator.connectionStatus(.connecting)
        StatusIndicator.connectionStatus(.failed)
        StatusIndicator.voiceStatus(.listening)
        StatusIndicator.voiceStatus(.thinking)
    }
    .padding()
}
