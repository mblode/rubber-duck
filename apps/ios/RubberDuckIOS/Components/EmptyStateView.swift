import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.spacing16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Theme.secondaryLabel)

            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Theme.label)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding(Theme.spacing32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
