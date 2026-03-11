import RubberDuckRemoteCore
import SwiftUI

struct SessionRow: View {
    let session: RemoteSessionSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.spacing12) {
            VStack(alignment: .leading, spacing: Theme.spacing4) {
                Text(session.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.label)

                Text(abbreviatedPath)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Theme.spacing4) {
                Circle()
                    .fill(session.isRunning ? Theme.statusGreen : Color(.quaternaryLabel))
                    .frame(width: 8, height: 8)

                Text(session.lastActiveAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
        .padding(.vertical, Theme.spacing4)
        .listRowBackground(isSelected ? Theme.accent.opacity(0.1) : Color.clear)
    }

    private var abbreviatedPath: String {
        let path = session.workspacePath
        guard let lastComponent = path.split(separator: "/").last else { return path }
        return String(lastComponent)
    }
}

#Preview {
    List {
        SessionRow(
            session: RemoteSessionSummary(
                id: "1",
                name: "rubber-duck",
                workspacePath: "/Users/mblode/Code/mblode/rubber-duck",
                isActive: true,
                isRunning: true,
                lastActiveAt: Date()
            ),
            isSelected: true
        )
        SessionRow(
            session: RemoteSessionSummary(
                id: "2",
                name: "other-project",
                workspacePath: "/Users/mblode/Code/other-project",
                isActive: false,
                isRunning: false,
                lastActiveAt: Date().addingTimeInterval(-3600)
            ),
            isSelected: false
        )
    }
}
