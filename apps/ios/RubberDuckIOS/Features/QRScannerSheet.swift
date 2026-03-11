import SwiftUI

struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    let onScan: (String) -> Void

    @State private var scannerError: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QRCodeScannerView(
                    onCode: { code in
                        onScan(code)
                        dismissSheet()
                    },
                    onError: { message in
                        scannerError = message
                    }
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    Text("Scan the Mac pairing QR")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Frame the QR code from your Mac. Rubber Duck will fill in the host and access token automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))

                    if let scannerError {
                        Text(scannerError)
                            .font(.footnote)
                            .foregroundStyle(Theme.statusOrange)
                    }
                }
                .padding(Theme.spacing16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusLarge, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .padding()
            }
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismissSheet() }
                }
            }
        }
    }

    private func dismissSheet() {
        isPresented = false
        dismiss()
    }
}
