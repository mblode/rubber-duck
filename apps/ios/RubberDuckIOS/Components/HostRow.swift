import RubberDuckRemoteCore
import SwiftUI

struct HostRow: View {
    let host: PairedRemoteHost
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.spacing12) {
            Image(systemName: isSelected ? "desktopcomputer.circle.fill" : "desktopcomputer")
                .font(.title2)
                .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryLabel)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: Theme.spacing4) {
                Text(host.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.label)

                Text(host.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)

                Text(host.lastConnectedAt ?? host.pairedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryLabel)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

#Preview {
    List {
        HostRow(
            host: PairedRemoteHost(
                id: "1",
                displayName: "MacBook Pro",
                baseURL: URL(string: "http://192.168.1.100:3000")!,
                authToken: "token",
                pairingCodeHint: "abc",
                pairedAt: Date()
            ),
            isSelected: true
        )
        HostRow(
            host: PairedRemoteHost(
                id: "2",
                displayName: "Mac Studio",
                baseURL: URL(string: "http://mac-studio.local:3000")!,
                authToken: "token",
                pairingCodeHint: "xyz",
                pairedAt: Date()
            ),
            isSelected: false
        )
    }
}
