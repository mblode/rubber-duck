import RubberDuckRemoteCore
import SwiftUI

struct MessageRow: View {
    let entry: RemoteConversationEntry

    var body: some View {
        Group {
            if entry.role == .tool || entry.role == .status {
                eventRow
            } else {
                bubbleRow
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: Theme.spacing16, bottom: 6, trailing: Theme.spacing16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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

    private var bubbleRow: some View {
        VStack(alignment: isUserMessage ? .trailing : .leading, spacing: Theme.spacing4) {
            HStack {
                if isUserMessage {
                    Spacer(minLength: 48)
                }

                Text(entry.text)
                    .font(.body)
                    .foregroundStyle(isUserMessage ? Color.white : Theme.label)
                    .textSelection(.enabled)
                    .padding(.horizontal, Theme.spacing12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isUserMessage ? Theme.accent : Color(.secondarySystemGroupedBackground))
                    )

                if !isUserMessage {
                    Spacer(minLength: 48)
                }
            }

            HStack(spacing: Theme.spacing8) {
                if isUserMessage {
                    Spacer()
                }

                Label(roleTitle, systemImage: roleIcon)
                    .labelStyle(.titleAndIcon)

                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))

                if !isUserMessage {
                    Spacer()
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.tertiaryLabel)
        }
        .padding(.vertical, Theme.spacing4)
    }

    private var eventRow: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            HStack(spacing: Theme.spacing8) {
                Label(roleTitle, systemImage: roleIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(roleTint)

                if let toolName = entry.metadata["tool"] {
                    Text(toolName.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.tertiaryLabel)
                }

                Spacer()

                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryLabel)
            }

            Text(entry.text)
                .font(entry.role == .tool ? .system(.footnote, design: .monospaced) : .footnote)
                .foregroundStyle(Theme.label)
                .textSelection(.enabled)
        }
        .padding(Theme.spacing12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var isUserMessage: Bool {
        entry.role == .user
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
