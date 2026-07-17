import AppKit
import SwiftUI

private struct SnipNoticeView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Transient centered HUD reporting the OCR snip outcome ("3 lines copied" /
/// "No text found"). Non-activating and mouse-transparent; auto-dismisses
/// after a short delay. Shown only after overlays are dismissed, so it never
/// competes with a key overlay window.
@MainActor
final class SnipNoticeController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(on screen: NSScreen, message: String) {
        dismiss()
        let view = NSHostingView(rootView: SnipNoticeView(message: message))
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
