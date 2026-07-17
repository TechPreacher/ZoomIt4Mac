import AppKit
import AVFoundation
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
    private let liveStream: LiveStreaming
    private let recorder: ScreenRecording
    private var overlays: [CGDirectDisplayID: OverlayWindowController] = [:]
    private(set) var snapshots: [CGDirectDisplayID: CGImage] = [:]
    private var activeTracker: ShapeTracker?
    private var breakTickTimer: Timer?
    private let recordingNotice = RecordingNoticeController()
    private let snipNotice = SnipNoticeController()
    private var recordingNoticeTimer: Timer?
    private var breakImage: CGImage?

    var onRecordingStateChange: ((Bool) -> Void)?
    private var lastReportedRecording = false
    /// A finished recording's URL waiting to be revealed in Finder once the
    /// session returns to .idle — activating Finder while a mode (draw/type/
    /// break/zoom) is active would steal keyboard focus from the overlay.
    private var pendingRevealURL: URL?

    var currentState: SessionState { machine.state }

    func currentSettings() -> Settings { machine.settings }

    init(settings: Settings, snapshotter: Snapshotting, permissions: PermissionCoordinator, liveStream: LiveStreaming, recorder: ScreenRecording) {
        self.machine = SessionStateMachine(settings: settings)
        self.snapshotter = snapshotter
        self.permissions = permissions
        self.liveStream = liveStream
        self.recorder = recorder
    }

    // MARK: - Event entry points

    func trigger(_ action: HotkeyAction) {
        if action == .toggleBreak {
            send(.breakRequested(now: CACurrentMediaTime()))
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screen(containing: mouse)?.frame
            ?? NSScreen.main?.frame ?? .zero
        send(.hotkey(action, mouse: mouse, screen: screen))
    }

    func send(_ event: SessionEvent) {
        let effects = machine.handle(event)
        for effect in effects { perform(effect) }
        // If Tab was held while the mode changed away from .draw (T into
        // type, Esc to zoom), keyUp may never route back here and tabHeld
        // would otherwise stick, forcing the next drag into ellipse mode.
        if case .draw = machine.state {} else { tabHeld = false }
        syncBreakTickTimer()
        if machine.isRecording != lastReportedRecording {
            lastReportedRecording = machine.isRecording
            onRecordingStateChange?(machine.isRecording)
        }
        if let url = pendingRevealURL, machine.state == .idle {
            pendingRevealURL = nil
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func applySettings(_ settings: Settings) {
        send(.settingsChanged(settings))
    }

    private func syncBreakTickTimer() {
        let inBreak = if case .breakTimer = machine.state { true } else { false }
        if inBreak && breakTickTimer == nil {
            breakTickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.send(.breakTick(now: CACurrentMediaTime()))
                }
            }
        } else if !inBreak, let timer = breakTickTimer {
            timer.invalidate()
            breakTickTimer = nil
        }
    }

    // MARK: - Input from overlay views

    func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 { // Esc
            send(.escape)
            return
        }

        if case .breakTimer = machine.state {
            switch event.keyCode {
            case 49: send(.breakPauseResume(now: CACurrentMediaTime())) // Space
            case 126: send(.breakAdjust(seconds: 60, now: CACurrentMediaTime()))  // ↑
            case 125: send(.breakAdjust(seconds: -60, now: CACurrentMediaTime())) // ↓
            default: break
            }
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

        switch machine.state {
        case .zoom, .liveZoom:
            switch event.keyCode {
            case 126: send(.zoomChanged(factor: 1.25)) // ↑
            case 125: send(.zoomChanged(factor: 0.8))  // ↓
            default: break
            }
            return
        default: break
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
            case "h": send(.keyCommand(.toggleHighlighter))
            case "x": send(.keyCommand(.toggleBlur))
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
           !chars.unicodeScalars.allSatisfy({
               CharacterSet.controlCharacters.contains($0) || (0xF700...0xF8FF).contains($0.value)
           }) {
            send(.textInput(chars))
        }
    }

    /// Map a global screen point into annotation (image) space for the
    /// active draw/type context: identity for plain draw or type, screen→image
    /// when drawing/typing on a frozen zoom.
    private func imageSpacePoint(for global: CGPoint) -> CGPoint {
        let zoom: ZoomContext?
        switch machine.state {
        case .draw(let ctx): zoom = ctx.zoom
        case .type(let ctx, _): zoom = ctx.zoom
        default: zoom = nil
        }
        guard let zoom else { return global }
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
        case .zoom, .liveZoom, .type:
            // zoom: enters draw; type: moves caret (both via the state machine)
            send(.leftMouseDown(imageSpacePoint(for: global)))
        case .draw(let ctx):
            activeTracker = ShapeTracker(
                shape: shapeKind(for: modifiers),
                start: imageSpacePoint(for: global),
                color: ctx.canvas.color,
                width: ctx.canvas.penWidth,
                style: ctx.canvas.penStyle
            )
        case .snip:
            send(.leftMouseDown(global))
        default:
            break
        }
    }

    func handleMouseDragged(global: CGPoint, modifiers: NSEvent.ModifierFlags) {
        if case .snip = machine.state {
            send(.mouseMoved(global))
            return
        }
        guard activeTracker != nil else { return }
        activeTracker?.update(imageSpacePoint(for: global))
        renderAll()
    }

    func handleMouseUp(global: CGPoint, modifiers: NSEvent.ModifierFlags) {
        if case .snip = machine.state {
            send(.leftMouseUp(global, optionHeld: modifiers.contains(.option)))
            return
        }
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
        case .zoom, .liveZoom:
            send(.zoomChanged(factor: deltaY > 0 ? 1.1 : 1 / 1.1))
        case .draw where modifiers.contains(.command):
            send(.penWidthChanged(delta: deltaY > 0 ? 1 : -1))
        case .breakTimer:
            send(.breakAdjust(seconds: deltaY > 0 ? 60 : -60, now: CACurrentMediaTime()))
        default:
            break
        }
    }

    func handleMagnify(_ magnification: CGFloat) {
        switch machine.state {
        case .zoom, .liveZoom: send(.zoomChanged(factor: 1 + magnification))
        default: break
        }
    }

    func handleMouseMoved(global: CGPoint) {
        switch machine.state {
        case .zoom, .liveZoom: send(.mouseMoved(global))
        default: break
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
        case .saveScreenshot:
            exportScreenshot(toClipboard: false)
        case .copyScreenshot:
            exportScreenshot(toClipboard: true)
        case .exportSnip(let selection, let alsoSave):
            exportSnip(selection: selection, alsoSave: alsoSave)
        case .recognizeText(let selection):
            recognizeText(selection: selection)
        case .playExpirySound:
            if let sound = NSSound(named: "Glass") {
                sound.play()
            } else {
                NSSound.beep()
            }
        case .startLiveStream:
            startLiveStream()
        case .stopLiveStream:
            liveStream.stop()
        case .freezeLiveFrame:
            freezeLiveFrame()
        case .startRecording:
            startRecording()
        case .stopRecording:
            recorder.stop { [weak self] url in
                guard let self, let url else { return }
                // Reveal now if idle, else defer until the session settles
                // (see pendingRevealURL) so Finder activation doesn't steal
                // keyboard focus from an active overlay mode.
                if self.machine.state == .idle {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    self.pendingRevealURL = url
                }
            }
        case .showRecordingNotice:
            showRecordingNotice()
        case .dismissRecordingNotice:
            dismissRecordingNotice()
        }
    }

    private func showRecordingNotice() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screen(containing: mouse) ?? NSScreen.main else {
            send(.recordingNoticeElapsed) // headless edge: skip straight to capture
            return
        }
        let combo = comboLabel(machine.settings.hotkeys.combo(for: .toggleRecord))
        recordingNotice.show(on: screen, stopComboLabel: combo)
        recordingNoticeTimer?.invalidate()
        recordingNoticeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.send(.recordingNoticeElapsed)
            }
        }
    }

    private func dismissRecordingNotice() {
        recordingNoticeTimer?.invalidate()
        recordingNoticeTimer = nil
        recordingNotice.dismiss()
    }

    private func startRecording() {
        guard permissions.hasScreenRecordingPermission() else {
            // Defer so the current effect batch finishes before the machine
            // unwinds; the system prompt is never hidden behind overlays.
            Task { @MainActor in
                self.permissions.requestPermission()
                self.send(.recordingFailed)
            }
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screen(containing: mouse) ?? NSScreen.main else {
            send(.recordingFailed)
            return
        }
        let recording = machine.settings.recording
        let displayID = screen.displayID

        // Screen-Recording preflight above already handles its own system
        // prompt via requestPermission(); this preflight is a *second*,
        // independent one for the mic authorization the recorder would
        // otherwise trigger from a background queue. Resolving it here first
        // lets us hide overlays for the prompt's duration. Accepted
        // limitation: if the mic prompt still manages to appear from within
        // an active mode in some edge case, it can sit behind the
        // .screenSaver-level overlay — the guidance alert (Esc, then
        // re-grant) covers recovery.
        guard recording.recordMicrophone,
              AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined,
              !overlays.isEmpty
        else {
            beginRecording(displayID: displayID, recording: recording)
            return
        }

        overlays.values.forEach { $0.close() }
        Task { @MainActor in
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            self.overlays.values.forEach { $0.show() }
            let mouse = NSEvent.mouseLocation
            let target = NSScreen.screen(containing: mouse) ?? NSScreen.main
            if let target { self.overlays[target.displayID]?.makeKey() }
            self.renderAll()
            // The user may have toggled recording off (⌃5) while the
            // permission prompt was up — machine.isRecording is the truth.
            guard self.machine.isRecording else { return }
            self.beginRecording(displayID: displayID, recording: recording)
        }
    }

    private func beginRecording(displayID: CGDirectDisplayID, recording: RecordingConfiguration) {
        recorder.start(
            displayID: displayID,
            codec: recording.codec,
            region: nil,
            microphone: recording.recordMicrophone,
            systemAudio: recording.recordSystemAudio,
            onError: { [weak self] _ in
                self?.send(.recordingFailed)
            }
        )
    }

    private func startLiveStream() {
        guard case .liveZoom(let ctx) = machine.state,
              let screen = NSScreen.screens.first(where: { $0.frame == ctx.screen }) else { return }
        guard permissions.hasScreenRecordingPermission() else {
            // Defer so the current effect batch (incl. showOverlays) finishes
            // before the machine unwinds and dismisses; the system prompt then
            // appears with no overlay above it.
            Task { @MainActor in
                self.permissions.requestPermission()
                self.send(.liveStreamFailed(.permissionDenied))
            }
            return
        }
        let displayID = screen.displayID
        liveStream.start(
            displayID: displayID,
            excluding: overlays.values.map(\.nsWindow),
            onFrame: { [weak self] surface in
                self?.overlays[displayID]?.pushLiveFrame(surface)
            },
            onError: { [weak self] failure in
                self?.send(.liveStreamFailed(failure))
            }
        )
    }

    private func freezeLiveFrame() {
        guard case .liveZoom(let ctx) = machine.state,
              let screen = NSScreen.screens.first(where: { $0.frame == ctx.screen }),
              let image = liveStream.latestFrameImage()
        else {
            send(.liveStreamFailed(.captureError))
            return
        }
        snapshots[screen.displayID] = image
        overlays[screen.displayID]?.snapshot = image
        send(.liveFrameFrozen)
    }

    private func captureScreens() {
        guard permissions.hasScreenRecordingPermission() else {
            switch machine.state {
            case .capturing(.zoom), .capturing(.snip):
                permissions.requestPermission()
            default:
                break // break timer falls back to a solid background instead
            }
            send(.captureFailed(.permissionDenied))
            return
        }
        Task {
            let result = await snapshotter.captureAllDisplays()
            switch result {
            case .success(let images):
                // The session may have already left .capturing (Esc, display
                // change) by the time this async capture completes. Applying
                // a stale snapshot would pollute the next session with a
                // frozen screenshot instead of a transparent overlay.
                guard case .capturing = machine.state else { return }
                snapshots = images
                send(.captureCompleted)
            case .failure(let failure):
                send(.captureFailed(failure))
            }
        }
    }

    private func showOverlays() {
        dismissOverlayWindows()
        if case .liveZoom(let ctx) = machine.state {
            guard let screen = NSScreen.screens.first(where: { $0.frame == ctx.screen }) else { return }
            let controller = OverlayWindowController(screen: screen, coordinator: self)
            controller.show()
            overlays[screen.displayID] = controller
            controller.makeKey()
            renderAll()
            return
        }
        breakImage = nil
        if case .breakTimer = machine.state,
           case .imageFile(let path) = machine.settings.breakTimer.background,
           let nsImage = NSImage(contentsOfFile: path),
           let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            breakImage = cg
        }
        for screen in NSScreen.screens {
            let controller = OverlayWindowController(screen: screen, coordinator: self)
            controller.snapshot = snapshots[screen.displayID]
            controller.breakImage = breakImage
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

    /// The screen being annotated: the zoom screen when drawing on a frozen
    /// zoom, else the screen under the mouse.
    private func activeAnnotationScreen() -> NSScreen? {
        let zoomScreenFrame: CGRect? = switch machine.state {
        case .draw(let ctx): ctx.zoom?.screen
        case .type(let ctx, _): ctx.zoom?.screen
        default: nil
        }
        if let zoomScreenFrame {
            return NSScreen.screens.first { $0.frame == zoomScreenFrame }
        }
        return NSScreen.screen(containing: NSEvent.mouseLocation) ?? NSScreen.main
    }

    private func activeOverlayView() -> NSView? {
        guard let screen = activeAnnotationScreen() else { return nil }
        return overlays[screen.displayID]?.compositingView
    }

    /// ⌘S/⌘C: capture the display as the user sees it (desktop or frozen
    /// zoom or board, WITH annotations — overlays are sharingType .readOnly).
    /// Falls back to compositing just the overlay view when screen capture
    /// is unavailable (no Screen Recording permission).
    private func exportScreenshot(toClipboard: Bool) {
        guard let screen = activeAnnotationScreen() else { return }
        let displayID = screen.displayID
        let screenSize = screen.frame.size

        if permissions.hasScreenRecordingPermission() {
            Task { @MainActor in
                let result = await self.snapshotter.captureDisplay(displayID)
                let image: NSImage? = switch result {
                case .success(let cg): NSImage(cgImage: cg, size: screenSize)
                case .failure: self.overlayFallbackImage()
                }
                guard let image else { return }
                self.deliverScreenshot(image, toClipboard: toClipboard)
            }
        } else if let image = overlayFallbackImage() {
            deliverScreenshot(image, toClipboard: toClipboard)
        }
    }

    private func overlayFallbackImage() -> NSImage? {
        guard let view = activeOverlayView() else { return nil }
        return ScreenshotComposer.image(of: view)
    }

    private func deliverScreenshot(_ image: NSImage, toClipboard: Bool) {
        if toClipboard {
            ScreenshotComposer.copy(image)
            return
        }
        // NSSavePanel.runModal() would appear behind our .screenSaver-level
        // overlay windows, making the app look frozen. Hide them for the
        // duration of the panel, then restore.
        overlays.values.forEach { $0.close() }
        ScreenshotComposer.save(image)
        overlays.values.forEach { $0.show() }
        let mouse = NSEvent.mouseLocation
        let target = NSScreen.screen(containing: mouse) ?? NSScreen.main
        if let target { overlays[target.displayID]?.makeKey() }
        renderAll()
    }

    /// Crop the frozen snapshot of the display that holds (most of) the
    /// selection. Shared by image snip (clipboard bitmap) and OCR snip.
    private func croppedSnip(selection: CGRect) -> (image: CGImage, displayID: CGDirectDisplayID, scale: CGFloat)? {
        let screen = NSScreen.screens.max { a, b in
            overlapArea(selection, a.frame) < overlapArea(selection, b.frame)
        }
        guard let screen, let snapshot = snapshots[screen.displayID] else { return nil }
        // Derive the scale from the snapshot itself — more robust than
        // backingScaleFactor if capture and display scale ever disagree.
        let scale = CGFloat(snapshot.width) / screen.frame.width
        guard let pixelRect = SnipGeometry.pixelCrop(
                  selection: selection, displayFrame: screen.frame, scale: scale
              ),
              let cropped = snapshot.cropping(to: pixelRect)
        else { return nil }
        return (cropped, screen.displayID, scale)
    }

    /// Copy the selection to the clipboard as an image; optionally offer a
    /// save panel.
    private func exportSnip(selection: CGRect, alsoSave: Bool) {
        guard let (cropped, _, scale) = croppedSnip(selection: selection) else {
            NSSound.beep()
            NSLog("snip export failed: no croppable selection")
            return
        }
        let pointSize = CGSize(width: CGFloat(cropped.width) / scale,
                               height: CGFloat(cropped.height) / scale)
        let image = NSImage(cgImage: cropped, size: pointSize)
        ScreenshotComposer.copy(image)
        guard alsoSave else { return }
        // .dismissOverlays runs later in this same effect batch; open the
        // panel on the next tick so it never sits under a .screenSaver
        // overlay window.
        Task { @MainActor in
            ScreenshotComposer.save(image, suggestedName: "ZoomIt Snip.png")
        }
    }

    /// Recognize text in the selection on-device and copy it; the HUD
    /// reports the outcome. The displayID (Sendable) crosses the recognition
    /// hop instead of NSScreen.
    private func recognizeText(selection: CGRect) {
        guard let (cropped, displayID, _) = croppedSnip(selection: selection) else {
            NSSound.beep()
            NSLog("ocr snip failed: no croppable selection")
            return
        }
        TextRecognitionService.recognizeText(in: cropped) { [weak self] lines in
            guard let self else { return }
            if !lines.isEmpty {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
            }
            let screen = NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main
            guard let screen else {
                NSLog("ocr snip: no screen available for notice HUD")
                return
            }
            if lines.isEmpty {
                self.snipNotice.show(on: screen, message: "No text found")
            } else {
                self.snipNotice.show(
                    on: screen,
                    message: lines.count == 1 ? "1 line copied" : "\(lines.count) lines copied"
                )
            }
        }
    }

    private func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
