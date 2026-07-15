import AppKit
import ZoomItCore

/// A borderless overlay window that can still become key/main, so keyboard
/// input (Esc, colors, T, ⌘Z/⌘S/⌘C, arrows) and key-window-only mouse events
/// (mouseMoved) actually reach it. Stock borderless NSWindow always returns
/// false from canBecomeKey.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

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
        self.window = OverlayWindow(
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
        // Explicitly setting this (even to its default) disables AppKit's
        // per-pixel transparency hit-testing, which would otherwise pass
        // clicks through the transparent plain-draw overlay to windows below.
        window.ignoresMouseEvents = false
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
