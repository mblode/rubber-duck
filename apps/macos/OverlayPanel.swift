import AppKit
import SwiftUI

enum OverlayState: Equatable {
    case listening
    case thinking
    case speaking
    case toolRunning(String)
    case error(String)
}

@MainActor
class OverlayPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayContentView>?
    private var dismissTimer: Timer?
    private var currentState: OverlayState = .listening
    private var pendingResizeWorkItem: DispatchWorkItem?

    static let shared = OverlayPanelController()

    private init() {}

    func show(state: OverlayState) {
        dismissTimer?.invalidate()

        // Always update for states with changing text; skip redundant updates for other states.
        if case .toolRunning = state {
            // Always update — tool name may change.
        } else if case .error = state {
            // Always update — error message may change.
        } else if state == currentState, panel != nil {
            panel?.orderFrontRegardless()
            return
        }

        currentState = state

        if panel == nil {
            createPanel()
        }

        hostingView?.rootView = OverlayContentView(state: state)
        scheduleResizePanel()
        panel?.orderFrontRegardless()

        let autoDismissDelay: TimeInterval? = {
            switch state {
            case .error: return 3.0
            default: return nil
            }
        }()

        if let delay = autoDismissDelay {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        pendingResizeWorkItem?.cancel()
        pendingResizeWorkItem = nil
        panel?.orderOut(nil)
    }

    private struct PanelLayout {
        let size: NSSize
        let origin: NSPoint

        static let minWidth: CGFloat = 120
        static let minHeight: CGFloat = 44
        static let bottomOffset: CGFloat = 80
    }

    private func computeLayout(for hostingView: NSHostingView<OverlayContentView>) -> PanelLayout {
        let idealSize = hostingView.fittingSize
        let width = max(idealSize.width, PanelLayout.minWidth)
        let height = max(idealSize.height, PanelLayout.minHeight)
        let origin: NSPoint
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            origin = NSPoint(x: screenFrame.midX - width / 2, y: screenFrame.minY + PanelLayout.bottomOffset)
        } else {
            origin = .zero
        }
        return PanelLayout(size: NSSize(width: width, height: height), origin: origin)
    }

    private func createPanel() {
        let contentView = OverlayContentView(state: currentState)
        let hosting = NSHostingView(rootView: contentView)
        let layout = computeLayout(for: hosting)

        hosting.frame = NSRect(origin: .zero, size: layout.size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: layout.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.contentView = hosting
        panel.setFrameOrigin(layout.origin)

        self.panel = panel
        self.hostingView = hosting
    }

    private func resizePanel() {
        guard let hosting = hostingView, let panel = panel else { return }
        let layout = computeLayout(for: hosting)
        let targetFrame = NSRect(origin: layout.origin, size: layout.size)
        if panel.frame.equalTo(targetFrame) {
            return
        }

        hosting.frame = NSRect(origin: .zero, size: layout.size)
        panel.setFrame(targetFrame, display: true, animate: false)
    }

    private func scheduleResizePanel() {
        pendingResizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.resizePanel()
        }
        pendingResizeWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }
}

struct OverlayContentView: View {
    let state: OverlayState

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .listening:
                Image(systemName: "mic.fill")
                    .foregroundStyle(.blue)
                    .symbolEffect(.variableColor.iterative)
                Text("Listening...")
                    .foregroundStyle(.primary)

            case .thinking:
                Image(systemName: "brain")
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
                Text("Thinking...")
                    .foregroundStyle(.primary)

            case .speaking:
                Image(systemName: "waveform")
                    .foregroundStyle(.green)
                    .symbolEffect(.variableColor.iterative)
                Text("Speaking...")
                    .foregroundStyle(.primary)

            case .toolRunning(let name):
                Image(systemName: "terminal.fill")
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse)
                Text("Running \(name)...")
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(String(msg.prefix(60)))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 400)
        .background(.ultraThinMaterial, in: Capsule())
        .fixedSize()
    }
}

// MARK: - Overlay Presenting Protocol

@MainActor
protocol OverlayPresenting: AnyObject {
    func show(state: OverlayState)
    func dismiss()
}

@MainActor
final class LiveOverlayPresenter: OverlayPresenting {
    static let shared = LiveOverlayPresenter()
    private init() {}

    func show(state: OverlayState) {
        OverlayPanelController.shared.show(state: state)
    }

    func dismiss() {
        OverlayPanelController.shared.dismiss()
    }
}
