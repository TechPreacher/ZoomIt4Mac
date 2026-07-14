import AppKit
import ZoomItCore

final class OverlayContentView: NSView {
    var snapshot: CGImage? {
        didSet { needsDisplay = true }
    }

    private let screenFrame: CGRect
    private weak var coordinator: SessionCoordinator?
    private var state: SessionState = .idle

    init(frame: CGRect, screen: NSScreen, coordinator: SessionCoordinator) {
        self.screenFrame = screen.frame
        self.coordinator = coordinator
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    func render(state: SessionState) {
        self.state = state
        needsDisplay = true
    }

    // MARK: - Coordinate mapping

    /// Window-local point (bottom-left origin) → global screen point.
    private func globalPoint(_ event: NSEvent) -> CGPoint {
        guard let window = event.window else { return event.locationInWindow }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    /// The zoom context that applies to THIS screen, if any.
    private var zoomContextForThisScreen: ZoomContext? {
        let ctx: ZoomContext? = switch state {
        case .zoom(let z): z
        case .draw(let d): d.zoom
        case .type(let d, _): d.zoom
        default: nil
        }
        guard let ctx, ctx.screen == screenFrame else { return nil }
        return ctx
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }

        if case .idle = state { return }
        if case .capturing = state { return }

        cg.saveGState()
        if let ctx = zoomContextForThisScreen {
            let visible = ZoomGeometry.visibleRect(mouse: ctx.mouse, screen: ctx.screen, level: ctx.level)
            // Local (window) coords: global minus screen origin.
            let visibleLocal = visible.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            cg.translateBy(x: -visibleLocal.minX * ctx.level, y: -visibleLocal.minY * ctx.level)
            cg.scaleBy(x: ctx.level, y: ctx.level)
        }

        if let snapshot {
            cg.interpolationQuality = .high
            cg.draw(snapshot, in: CGRect(origin: .zero, size: screenFrame.size))
        }

        drawAnnotations(in: cg) // no-op until Task 17
        cg.restoreGState()
    }

    func drawAnnotations(in cg: CGContext) {
        // Task 17 implements background fill, annotations, preview, type caret.
    }

    // MARK: - Input forwarding

    override func keyDown(with event: NSEvent) {
        coordinator?.handleKeyDown(event)
    }

    override func mouseDown(with event: NSEvent) {
        coordinator?.handleMouseDown(global: globalPoint(event), modifiers: event.modifierFlags)
    }

    override func mouseDragged(with event: NSEvent) {
        coordinator?.handleMouseDragged(global: globalPoint(event), modifiers: event.modifierFlags)
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.handleMouseUp(global: globalPoint(event), modifiers: event.modifierFlags)
    }

    override func rightMouseDown(with event: NSEvent) {
        coordinator?.handleRightMouseDown()
    }

    override func scrollWheel(with event: NSEvent) {
        coordinator?.handleScroll(deltaY: event.scrollingDeltaY, modifiers: event.modifierFlags)
    }

    override func magnify(with event: NSEvent) {
        coordinator?.handleMagnify(event.magnification)
    }

    override func mouseMoved(with event: NSEvent) {
        coordinator?.handleMouseMoved(global: globalPoint(event))
    }
}
