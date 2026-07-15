import AppKit
import ZoomItCore

final class OverlayContentView: NSView {
    var snapshot: CGImage? {
        didSet { needsDisplay = true }
    }

    private let screenFrame: CGRect
    private weak var coordinator: SessionCoordinator?
    private var state: SessionState = .idle

    // Zoom-entry animation: eases the DISPLAYED level from 1× to the
    // machine's level on fresh zoom entry (ZoomIt-style smooth zoom).
    // 1.0 means "no animation in progress".
    private var zoomEntryProgress: CGFloat = 1
    private var zoomEntryTimer: Timer?
    private static let zoomEntryDuration: TimeInterval = 0.25

    init(frame: CGRect, screen: NSScreen, coordinator: SessionCoordinator) {
        self.screenFrame = screen.frame
        self.coordinator = coordinator
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    func render(state: SessionState) {
        let wasZoomed = zoomBearing(self.state)
        self.state = state
        if zoomBearing(state) && !wasZoomed && zoomContextForThisScreen != nil {
            startZoomEntryAnimation()
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    /// Whether a state carries a zoom context (zoom itself or draw/type on zoom).
    private func zoomBearing(_ state: SessionState) -> Bool {
        switch state {
        case .zoom: return true
        case .draw(let d): return d.zoom != nil
        case .type(let d, _): return d.zoom != nil
        default: return false
        }
    }

    private func startZoomEntryAnimation() {
        zoomEntryTimer?.invalidate()
        zoomEntryProgress = 0
        let start = CACurrentMediaTime()
        zoomEntryTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            // Timers fire on the main run loop; hop into MainActor for view
            // state, but invalidate outside so the timer isn't captured by
            // the isolated closure (Swift 6 sending diagnostics).
            let finished = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.window != nil else { return true }
                let t = min((CACurrentMediaTime() - start) / Self.zoomEntryDuration, 1)
                // Ease-out cubic: fast start, gentle landing.
                self.zoomEntryProgress = 1 - pow(1 - CGFloat(t), 3)
                self.needsDisplay = true
                if t >= 1 { self.zoomEntryTimer = nil }
                return t >= 1
            }
            if finished { timer.invalidate() }
        }
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
            // During zoom entry, ease the displayed level from 1× up to the
            // machine's level; the pan rect recomputes per frame so the view
            // stays centered on the mouse throughout.
            let level = 1 + (ctx.level - 1) * zoomEntryProgress
            let visible = ZoomGeometry.visibleRect(mouse: ctx.mouse, screen: ctx.screen, level: level)
            // Local (window) coords: global minus screen origin.
            let visibleLocal = visible.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            cg.translateBy(x: -visibleLocal.minX * level, y: -visibleLocal.minY * level)
            cg.scaleBy(x: level, y: level)
        }

        if let snapshot {
            cg.interpolationQuality = .high
            cg.draw(snapshot, in: CGRect(origin: .zero, size: screenFrame.size))
        }

        drawAnnotations(in: cg)
        cg.restoreGState()
    }

    func drawAnnotations(in cg: CGContext) {
        let drawContext: DrawContext? = switch state {
        case .draw(let d): d
        case .type(let d, _): d
        default: nil
        }
        guard let drawContext else { return }

        // Board background (whiteboard/blackboard) under the ink.
        switch drawContext.canvas.background {
        case .white: cg.setFillColor(.white)
        case .black: cg.setFillColor(.black)
        case .transparent: break
        }
        if drawContext.canvas.background != .transparent {
            cg.fill(CGRect(origin: .zero, size: screenFrame.size))
        }

        // Annotation coords are global; this view is one screen — shift into local space.
        cg.saveGState()
        cg.translateBy(x: -screenFrame.minX, y: -screenFrame.minY)

        for annotation in drawContext.canvas.annotations {
            draw(annotation, in: cg)
        }
        if let preview = coordinator?.currentPreview() {
            draw(preview, in: cg)
        }
        if case let .type(_, tool) = state, let origin = tool.origin {
            drawTypeRun(text: tool.text + "▏", at: origin,
                        color: drawContext.canvas.color, fontSize: tool.fontSize)
        }
        cg.restoreGState()
    }

    private func nsColor(_ color: AnnotationColor) -> NSColor {
        switch color {
        case .red: .systemRed
        case .green: .systemGreen
        case .blue: .systemBlue
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .pink: .systemPink
        }
    }

    private func draw(_ annotation: Annotation, in cg: CGContext) {
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        switch annotation {
        case let .stroke(points, color, width):
            guard points.count >= 2 else { return }
            cg.setStrokeColor(nsColor(color).cgColor)
            cg.setLineWidth(width)
            cg.beginPath()
            cg.move(to: points[0])
            for p in points.dropFirst() { cg.addLine(to: p) }
            cg.strokePath()
        case let .line(from, to, color, width):
            strokeSegments([(from, to)], color: color, width: width, in: cg)
        case let .arrow(from, to, color, width):
            let head = Annotation.arrowHead(from: from, to: to, length: max(10, width * 4))
            strokeSegments([(from, to), (to, head.left), (to, head.right)],
                           color: color, width: width, in: cg)
        case let .rectangle(rect, color, width):
            cg.setStrokeColor(nsColor(color).cgColor)
            cg.setLineWidth(width)
            cg.stroke(rect)
        case let .ellipse(rect, color, width):
            cg.setStrokeColor(nsColor(color).cgColor)
            cg.setLineWidth(width)
            cg.strokeEllipse(in: rect)
        case let .text(string, at, color, fontSize):
            drawTypeRun(text: string, at: at, color: color, fontSize: fontSize)
        }
    }

    private func strokeSegments(_ segments: [(CGPoint, CGPoint)], color: AnnotationColor,
                                width: CGFloat, in cg: CGContext) {
        cg.setStrokeColor(nsColor(color).cgColor)
        cg.setLineWidth(width)
        cg.beginPath()
        for (a, b) in segments {
            cg.move(to: a)
            cg.addLine(to: b)
        }
        cg.strokePath()
    }

    private func drawTypeRun(text: String, at point: CGPoint, color: AnnotationColor, fontSize: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: nsColor(color),
        ]
        NSAttributedString(string: text, attributes: attributes).draw(at: point)
    }

    // MARK: - Input forwarding

    override func keyDown(with event: NSEvent) {
        coordinator?.handleKeyDown(event)
    }

    override func keyUp(with event: NSEvent) {
        coordinator?.handleKeyUp(event)
    }

    override func resetCursorRects() {
        switch state {
        case .draw, .type:
            addCursorRect(bounds, cursor: .crosshair)
        default:
            addCursorRect(bounds, cursor: .arrow)
        }
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
