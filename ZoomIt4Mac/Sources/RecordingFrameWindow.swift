import AppKit

/// Thin border marking the recorded region for the duration of a region
/// recording. sharingType == .none keeps the window out of every capture,
/// so the frame itself is never part of the recording.
@MainActor
final class RecordingFrameController {
    private var window: NSWindow?

    /// rect: recorded bounds in global screen points (bottom-left origin).
    func show(around rect: CGRect) {
        dismiss()
        // Stroke sits just outside the recorded bounds so no content is covered.
        let frameRect = rect.insetBy(dx: -3, dy: -3)
        let window = NSWindow(
            contentRect: frameRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = RecordingFrameView(frame: NSRect(origin: .zero, size: frameRect.size))
        window.orderFrontRegardless()
        self.window = window
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class RecordingFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        NSColor.systemRed.setStroke()
        path.stroke()
    }
}
