import AppKit
import ZoomItCore

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}

@MainActor
final class SessionCoordinator {
    private var machine: SessionStateMachine
    private let snapshotter: Snapshotting
    private let permissions: PermissionCoordinator
    private var overlays: [CGDirectDisplayID: OverlayWindowController] = [:]
    private(set) var snapshots: [CGDirectDisplayID: CGImage] = [:]
    private var activeTracker: ShapeTracker?

    var currentState: SessionState { machine.state }

    init(settings: Settings, snapshotter: Snapshotting, permissions: PermissionCoordinator) {
        self.machine = SessionStateMachine(settings: settings)
        self.snapshotter = snapshotter
        self.permissions = permissions
    }

    // MARK: - Event entry points

    func trigger(_ action: HotkeyAction) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screen(containing: mouse)?.frame
            ?? NSScreen.main?.frame ?? .zero
        send(.hotkey(action, mouse: mouse, screen: screen))
    }

    func send(_ event: SessionEvent) {
        let effects = machine.handle(event)
        for effect in effects { perform(effect) }
    }

    func applySettings(_ settings: Settings) {
        send(.settingsChanged(settings))
    }

    // MARK: - Input from overlay views (zoom mode; draw/type in Task 17)

    func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 { // Esc
            send(.escape)
            return
        }

        if case .type = machine.state {
            handleTypeKeyDown(event)
            return
        }

        let cmd = event.modifierFlags.contains(.command)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if cmd {
            switch chars {
            case "z": send(.keyCommand(.undo))
            case "s": send(.keyCommand(.save))
            case "c": send(.keyCommand(.copy))
            default: break
            }
            return
        }

        if case .zoom = machine.state {
            switch event.keyCode {
            case 126: send(.zoomChanged(factor: 1.25)) // ↑
            case 125: send(.zoomChanged(factor: 0.8))  // ↓
            default: break
            }
            return
        }

        if case .draw = machine.state {
            switch chars {
            case "r": send(.keyCommand(.color(.red)))
            case "g": send(.keyCommand(.color(.green)))
            case "b": send(.keyCommand(.color(.blue)))
            case "o": send(.keyCommand(.color(.orange)))
            case "y": send(.keyCommand(.color(.yellow)))
            case "p": send(.keyCommand(.color(.pink)))
            case "e": send(.keyCommand(.eraseAll))
            case "w": send(.keyCommand(.whiteboard))
            case "k": send(.keyCommand(.blackboard))
            case "t": send(.keyCommand(.enterType))
            default:
                if event.keyCode == 48 { tabHeld = true } // Tab: ellipse modifier
            }
        }
    }

    func handleKeyUp(_ event: NSEvent) {
        if event.keyCode == 48 { tabHeld = false }
    }

    private var tabHeld = false

    private func handleTypeKeyDown(_ event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "+", "=": send(.keyCommand(.fontIncrease))
            case "-": send(.keyCommand(.fontDecrease))
            default: break
            }
            return
        }
        if event.keyCode == 51 { // Delete
            send(.deleteBackward)
            return
        }
        if let chars = event.characters, !chars.isEmpty,
           !chars.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) {
            send(.textInput(chars))
        }
    }

    /// Map a global screen point into annotation (image) space for the
    /// active draw context: identity for plain draw, screen→image when
    /// drawing on a frozen zoom.
    private func annotationPoint(for global: CGPoint) -> CGPoint {
        guard case let .draw(ctx) = machine.state, let zoom = ctx.zoom else { return global }
        let visible = ZoomGeometry.visibleRect(mouse: zoom.mouse, screen: zoom.screen, level: zoom.level)
        return ZoomGeometry.screenToImage(global, visibleRect: visible, screen: zoom.screen)
    }

    private func shapeKind(for modifiers: NSEvent.ModifierFlags) -> ShapeKind {
        let shift = modifiers.contains(.shift)
        let control = modifiers.contains(.control)
        if tabHeld { return .ellipse }
        if control && shift { return .arrow }
        if control { return .rectangle }
        if shift { return .line }
        return .freehand
    }

    func handleMouseDown(global: CGPoint, modifiers: NSEvent.ModifierFlags) {
        switch machine.state {
        case .zoom, .type:
            // zoom: enters draw; type: moves caret (both via the state machine)
            send(.leftMouseDown(annotationPointForType(global)))
        case .draw(let ctx):
            activeTracker = ShapeTracker(
                shape: shapeKind(for: modifiers),
                start: annotationPoint(for: global),
                color: ctx.canvas.color,
                width: ctx.canvas.penWidth
            )
        default:
            break
        }
    }

    /// Type-mode caret uses the same image-space mapping as annotations.
    private func annotationPointForType(_ global: CGPoint) -> CGPoint {
        guard case let .type(ctx, _) = machine.state, let zoom = ctx.zoom else { return global }
        let visible = ZoomGeometry.visibleRect(mouse: zoom.mouse, screen: zoom.screen, level: zoom.level)
        return ZoomGeometry.screenToImage(global, visibleRect: visible, screen: zoom.screen)
    }

    func handleMouseDragged(global: CGPoint, modifiers: NSEvent.ModifierFlags) {
        guard activeTracker != nil else { return }
        activeTracker?.update(annotationPoint(for: global))
        renderAll()
    }

    func handleMouseUp(global: CGPoint, modifiers: NSEvent.ModifierFlags) {
        guard let tracker = activeTracker else { return }
        activeTracker = nil
        if let annotation = tracker.finish() {
            send(.annotationAdded(annotation))
        } else {
            renderAll()
        }
    }

    func handleRightMouseDown() {
        send(.rightMouseAction)
    }

    func handleScroll(deltaY: CGFloat, modifiers: NSEvent.ModifierFlags) {
        guard deltaY != 0 else { return }
        switch machine.state {
        case .zoom:
            send(.zoomChanged(factor: deltaY > 0 ? 1.1 : 1 / 1.1))
        case .draw where modifiers.contains(.command):
            send(.penWidthChanged(delta: deltaY > 0 ? 1 : -1))
        default:
            break
        }
    }

    func handleMagnify(_ magnification: CGFloat) {
        if case .zoom = machine.state {
            send(.zoomChanged(factor: 1 + magnification))
        }
    }

    func handleMouseMoved(global: CGPoint) {
        if case .zoom = machine.state {
            send(.mouseMoved(global))
        }
    }

    func currentPreview() -> Annotation? {
        activeTracker?.preview()
    }

    // MARK: - Effects

    private func perform(_ effect: SessionEffect) {
        switch effect {
        case .captureScreens:
            captureScreens()
        case .showOverlays:
            showOverlays()
        case .dismissOverlays:
            dismissOverlays()
        case .render:
            renderAll()
        case .showPermissionGuidance:
            permissions.showGuidanceAlert()
        case .notifyCaptureFailure:
            NSSound.beep()
            NSLog("screen capture failed")
        case .saveScreenshot, .copyScreenshot:
            break // Task 18 replaces with ScreenshotComposer calls
        }
    }

    private func captureScreens() {
        guard permissions.hasScreenRecordingPermission() else {
            permissions.requestPermission()
            send(.captureFailed(.permissionDenied))
            return
        }
        Task {
            let result = await snapshotter.captureAllDisplays()
            switch result {
            case .success(let images):
                snapshots = images
                send(.captureCompleted)
            case .failure(let failure):
                send(.captureFailed(failure))
            }
        }
    }

    private func showOverlays() {
        dismissOverlayWindows()
        for screen in NSScreen.screens {
            let controller = OverlayWindowController(screen: screen, coordinator: self)
            controller.snapshot = snapshots[screen.displayID]
            controller.show()
            overlays[screen.displayID] = controller
        }
        // Key window = the one under the mouse, so it gets keyboard input.
        let mouse = NSEvent.mouseLocation
        let target = NSScreen.screen(containing: mouse) ?? NSScreen.main
        if let target { overlays[target.displayID]?.makeKey() }
        renderAll()
    }

    private func dismissOverlays() {
        dismissOverlayWindows()
        snapshots.removeAll()
    }

    private func dismissOverlayWindows() {
        overlays.values.forEach { $0.close() }
        overlays.removeAll()
    }

    private func renderAll() {
        for controller in overlays.values {
            controller.render(state: machine.state)
        }
    }
}
