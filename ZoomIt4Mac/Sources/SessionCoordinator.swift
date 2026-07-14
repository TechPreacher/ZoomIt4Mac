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
        if case .zoom = machine.state {
            switch event.keyCode {
            case 126: send(.zoomChanged(factor: 1.25)) // ↑
            case 125: send(.zoomChanged(factor: 0.8))  // ↓
            default: break
            }
        }
    }

    func handleMouseDown(global: CGPoint, modifiers: NSEvent.ModifierFlags) {
        send(.leftMouseDown(global))
    }

    func handleMouseDragged(global: CGPoint, modifiers: NSEvent.ModifierFlags) {}

    func handleMouseUp(global: CGPoint, modifiers: NSEvent.ModifierFlags) {}

    func handleRightMouseDown() {
        send(.rightMouseAction)
    }

    func handleScroll(deltaY: CGFloat, modifiers: NSEvent.ModifierFlags) {
        guard deltaY != 0 else { return }
        if case .zoom = machine.state {
            send(.zoomChanged(factor: deltaY > 0 ? 1.1 : 1 / 1.1))
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

    func currentPreview() -> Annotation? { nil } // in-flight shape: Task 17

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
