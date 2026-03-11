import SwiftUI

struct ComposerBar: View {
    @Binding var text: String
    let isDisabled: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.spacing8) {
            TextField("Send a prompt...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(Theme.spacing12)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.accent))
                    .foregroundStyle(.white)
            }
            .disabled(isSendDisabled)
            .opacity(isSendDisabled ? 0.4 : 1.0)
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing8)
        .background(Color(.systemBackground))
    }

    private var isSendDisabled: Bool {
        isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    VStack {
        Spacer()
        ComposerBar(text: .constant("Hello world"), isDisabled: false, onSend: {})
        ComposerBar(text: .constant(""), isDisabled: true, onSend: {})
    }
}
