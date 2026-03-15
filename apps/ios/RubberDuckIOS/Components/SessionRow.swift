import RubberDuckRemoteCore
import SwiftUI

struct SessionRow: View {
    let session: RemoteSessionSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.spacing12) {
            Image(systemName: isSelected ? "folder.fill" : "folder")
                .font(.title3)
                .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryLabel)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: Theme.spacing4) {
                Text(session.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.label)

                Text(session.workspacePath)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Theme.spacing4) {
                HStack(spacing: Theme.spacing4) {
                    Image(systemName: session.isRunning ? "circle.fill" : "pause.circle.fill")
                        .font(.system(size: session.isRunning ? 8 : 12))
                    Text(session.isRunning ? "Live" : "Stopped")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(session.isRunning ? Theme.statusGreen : Theme.tertiaryLabel)

                Text(session.lastActiveAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryLabel)

                if isSelected {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(isSelected ? Theme.accent.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
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
