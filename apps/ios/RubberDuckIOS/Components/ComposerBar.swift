import SwiftUI

struct ComposerBar: View {
    @Binding var text: String
    let isDisabled: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.spacing12) {
            TextField("Send a prompt...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit(submitIfPossible)
                .padding(.horizontal, Theme.spacing12)
                .padding(.vertical, 10)
                .accessibilityIdentifier("composer-text-field")
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

            Button(action: submitIfPossible) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("composer-send-button")
            .accessibilityLabel("Send")
            .disabled(isSendDisabled)
            .opacity(isSendDisabled ? 0.4 : 1.0)
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.top, Theme.spacing8)
        .padding(.bottom, Theme.spacing8)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var isSendDisabled: Bool {
        isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitIfPossible() {
        guard !isSendDisabled else {
            return
        }

        onSend()
    }
}

#Preview {
    VStack {
        Spacer()
        ComposerBar(text: .constant("Hello world"), isDisabled: false, onSend: {})
        ComposerBar(text: .constant(""), isDisabled: true, onSend: {})
    }
}
