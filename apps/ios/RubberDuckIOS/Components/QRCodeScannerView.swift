import AVFoundation
import SwiftUI
import UIKit

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCode: @MainActor (String) -> Void
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onError: onError)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, ScannerViewControllerDelegate {
        private let onCode: @MainActor (String) -> Void
        private let onError: @MainActor (String) -> Void

        init(
            onCode: @escaping @MainActor (String) -> Void,
            onError: @escaping @MainActor (String) -> Void
        ) {
            self.onCode = onCode
            self.onError = onError
        }

        func scannerViewController(_ controller: ScannerViewController, didScan code: String) {
            Task { @MainActor in
                onCode(code)
            }
        }

        func scannerViewController(_ controller: ScannerViewController, didFail message: String) {
            Task { @MainActor in
                onError(message)
            }
        }
    }
}

protocol ScannerViewControllerDelegate: AnyObject {
    func scannerViewController(_ controller: ScannerViewController, didScan code: String)
    func scannerViewController(_ controller: ScannerViewController, didFail message: String)
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: ScannerViewControllerDelegate?

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "co.blode.rubber-duck.ios.qr-scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var didEmitCode = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopRunning()
    }

    private func configureIfNeeded() {
        guard !isConfigured else {
            startRunning()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureCaptureSession()
                    } else {
                        self.delegate?.scannerViewController(
                            self,
                            didFail: "Camera access is required to scan the pairing QR code."
                        )
                    }
                }
            }
        case .denied, .restricted:
            delegate?.scannerViewController(
                self,
                didFail: "Camera access is denied. Enable it in Settings to scan the pairing QR code."
            )
        @unknown default:
            delegate?.scannerViewController(
                self,
                didFail: "This device does not allow camera access for QR scanning."
            )
        }
    }

    private func configureCaptureSession() {
        guard !isConfigured else {
            startRunning()
            return
        }

        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            delegate?.scannerViewController(self, didFail: "No camera is available on this device.")
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            guard captureSession.canAddInput(videoInput) else {
                delegate?.scannerViewController(self, didFail: "Unable to configure the camera input.")
                return
            }
            captureSession.addInput(videoInput)

            let metadataOutput = AVCaptureMetadataOutput()
            guard captureSession.canAddOutput(metadataOutput) else {
                delegate?.scannerViewController(self, didFail: "Unable to configure the QR scanner.")
                return
            }
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.qr]

            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.layer.bounds
            view.layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer
            isConfigured = true
            startRunning()
        } catch {
            delegate?.scannerViewController(
                self,
                didFail: "Failed to start the camera: \(error.localizedDescription)"
            )
        }
    }

    private func startRunning() {
        guard isConfigured else {
            return
        }

        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else {
                return
            }
            self.captureSession.startRunning()
        }
    }

    private func stopRunning() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else {
                return
            }
            self.captureSession.stopRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didEmitCode,
              let code = metadataObjects
                .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                .first(where: { $0.type == .qr })?
                .stringValue,
              !code.isEmpty else {
            return
        }

        didEmitCode = true
        stopRunning()
        delegate?.scannerViewController(self, didScan: code)
    }
}
