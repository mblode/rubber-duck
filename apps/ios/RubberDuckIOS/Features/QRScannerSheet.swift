import SwiftUI

struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    let onScan: (String) -> Void

    @State private var scannerError: String?

    var body: some View {
        NavigationStack {
            ZStack {
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

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                    .frame(width: 260, height: 260)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
            }
            .background(.black)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    Label("Scan the pairing QR on your Mac", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Frame the code inside the guide. Rubber Duck will fill in the Mac address and access token automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))

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
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
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
