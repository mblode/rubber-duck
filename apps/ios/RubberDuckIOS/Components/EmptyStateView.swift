import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let actionTitle, let action {
                ContentUnavailableView {
                    Label(title, systemImage: icon)
                } description: {
                    Text(subtitle)
                } actions: {
                    Button(actionTitle, action: action)
                        .accessibilityIdentifier("empty-state-action-button")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            } else {
                ContentUnavailableView(
                    title,
                    systemImage: icon,
                    description: Text(subtitle)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.spacing24)
    }
}

#Preview("With action") {
    EmptyStateView(
        icon: "desktopcomputer",
        title: "No Macs Paired",
        subtitle: "Pair this phone with your Mac to start voice coding against a live repo.",
        actionTitle: "Pair a Mac",
        action: {}
    )
}

#Preview("Without action") {
    EmptyStateView(
        icon: "text.bubble",
        title: "No Transcript Yet",
        subtitle: "Hold the talk button to start a voice turn, or send a typed prompt."
    )
}
