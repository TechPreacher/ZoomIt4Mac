import AppKit
import ZoomItCore

@MainActor
final class OverlayWindowController {
    private let window: NSWindow
    private let contentView: OverlayContentView
    let screen: NSScreen

    var snapshot: CGImage? {
        didSet { contentView.snapshot = snapshot }
    }

    var compositingView: NSView { contentView }

    init(screen: NSScreen, coordinator: SessionCoordinator) {
        self.screen = screen
        self.contentView = OverlayContentView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            screen: screen,
            coordinator: coordinator
        )
        self.window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.sharingType = .none // never capture our own overlay
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = contentView
    }

    func show() {
        window.orderFrontRegardless()
    }

    func makeKey() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(contentView)
    }

    func close() {
        window.orderOut(nil)
    }

    func render(state: SessionState) {
        contentView.render(state: state)
    }
}
