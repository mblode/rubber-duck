import RubberDuckRemoteCore
import SwiftUI

struct MessageRow: View {
    let entry: RemoteConversationEntry

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing8) {
            Image(systemName: roleIcon)
                .font(.caption)
                .foregroundStyle(roleTint)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Theme.spacing4) {
                HStack(spacing: Theme.spacing8) {
                    Text(roleTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(roleTint)

                    if let toolName = entry.metadata["tool"] {
                        Text(toolName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.tertiaryLabel)
                    }

                    Spacer()

                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryLabel)
                }

                Text(entry.text)
                    .font(.body)
                    .foregroundStyle(Theme.label)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, Theme.spacing4)
    }

    var roleTitle: String {
        switch entry.role {
        case .user: "You"
        case .assistant: "Duck"
        case .tool: "Tool"
        case .status: "Status"
        }
    }

    var roleIcon: String {
        switch entry.role {
        case .user: "person.fill"
        case .assistant: "cpu"
        case .tool: "wrench.fill"
        case .status: "info.circle"
        }
    }

    var roleTint: Color {
        switch entry.role {
        case .user: Theme.accent
        case .assistant: Theme.statusGreen
        case .tool: Color(.systemBlue)
        case .status: Theme.secondaryLabel
        }
    }
}

#Preview {
    List {
        MessageRow(entry: RemoteConversationEntry(
            role: .user,
            text: "List all files in the src directory",
            timestamp: Date()
        ))
        MessageRow(entry: RemoteConversationEntry(
            role: .assistant,
            text: "I'll list the files in src for you. Let me run that command.",
            timestamp: Date()
        ))
        MessageRow(entry: RemoteConversationEntry(
            role: .tool,
            text: "src/\n  main.swift\n  app.swift",
            timestamp: Date(),
            metadata: ["tool": "bash"]
        ))
        MessageRow(entry: RemoteConversationEntry(
            role: .status,
            text: "Session connected",
            timestamp: Date()
        ))
    }
    .listStyle(.plain)
}
