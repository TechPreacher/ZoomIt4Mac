import Testing
import CoreGraphics
import ZoomItCore

let testScreen = CGRect(x: 0, y: 0, width: 1000, height: 800)
let testMouse = CGPoint(x: 500, y: 400)

func machine(_ settings: Settings = .default) -> SessionStateMachine {
    SessionStateMachine(settings: settings)
}

/// Drive a machine into the zoom state.
func zoomedMachine(_ settings: Settings = .default) -> SessionStateMachine {
    var m = machine(settings)
    m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
    m.handle(.captureCompleted)
    return m
}

struct SessionLifecycleTests {
    @Test func zoomHotkeyStartsCapture() {
        var m = machine()
        let fx = m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        #expect(fx == [.captureScreens])
        #expect(m.state == .capturing(.zoom(mouse: testMouse, screen: testScreen)))
    }

    @Test func captureCompletedEntersZoomAtDefaultLevel() {
        var m = machine()
        m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        let fx = m.handle(.captureCompleted)
        #expect(fx == [.showOverlays, .render])
        #expect(m.state == .zoom(ZoomContext(level: 2.0, mouse: testMouse, screen: testScreen)))
    }

    @Test func permissionDeniedReturnsToIdleWithGuidance() {
        var m = machine()
        m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        let fx = m.handle(.captureFailed(.permissionDenied))
        #expect(fx == [.showPermissionGuidance])
        #expect(m.state == .idle)
    }

    @Test func captureErrorNotifies() {
        var m = machine()
        m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        let fx = m.handle(.captureFailed(.captureError))
        #expect(fx == [.notifyCaptureFailure])
        #expect(m.state == .idle)
    }

    @Test func escapeDuringCaptureCancels() {
        var m = machine()
        m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        m.handle(.escape)
        #expect(m.state == .idle)
    }

    @Test func captureFailedInIdleIsIgnored() {
        var m = machine()
        let fx = m.handle(.captureFailed(.captureError))
        #expect(fx.isEmpty)
        #expect(m.state == .idle)
    }

    @Test func drawHotkeyEntersPlainDrawWithSettingsPen() {
        var settings = Settings.default
        settings.penColor = .green
        settings.penWidth = 7
        var m = machine(settings)
        let fx = m.handle(.hotkey(.toggleDraw, mouse: testMouse, screen: testScreen))
        #expect(fx == [.showOverlays, .render])
        guard case let .draw(ctx) = m.state else { Issue.record("expected draw"); return }
        #expect(ctx.zoom == nil)
        #expect(ctx.canvas.color == .green)
        #expect(ctx.canvas.penWidth == 7)
    }

    @Test func zoomExitsOnEscape() {
        var m = zoomedMachine()
        let fx = m.handle(.escape)
        #expect(fx == [.dismissOverlays])
        #expect(m.state == .idle)
    }

    @Test func zoomHotkeyTogglesOff() {
        var m = zoomedMachine()
        let fx = m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        #expect(fx == [.dismissOverlays])
        #expect(m.state == .idle)
    }

    @Test func rightClickExitsZoom() {
        var m = zoomedMachine()
        #expect(m.handle(.rightMouseAction) == [.dismissOverlays])
        #expect(m.state == .idle)
    }

    @Test func displayChangeForcesIdleFromZoom() {
        var m = zoomedMachine()
        let fx = m.handle(.displayConfigurationChanged)
        #expect(fx == [.dismissOverlays])
        #expect(m.state == .idle)
    }

    @Test func displayChangeInIdleDoesNothing() {
        var m = machine()
        #expect(m.handle(.displayConfigurationChanged).isEmpty)
    }

    @Test func settingsChangedAffectsNextZoomEntry() {
        var m = machine()
        var s = Settings.default
        s.defaultZoomLevel = 4
        m.handle(.settingsChanged(s))
        m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        m.handle(.captureCompleted)
        guard case let .zoom(ctx) = m.state else { Issue.record("expected zoom"); return }
        #expect(ctx.level == 4)
    }
}

struct SessionZoomInteractionTests {
    @Test func zoomFactorMultipliesAndRenders() {
        var m = zoomedMachine() // at 2.0
        let fx = m.handle(.zoomChanged(factor: 1.5))
        #expect(fx == [.render])
        guard case let .zoom(ctx) = m.state else { Issue.record("expected zoom"); return }
        #expect(ctx.level == 3.0)
    }

    @Test func zoomClampsAtMax() {
        var m = zoomedMachine()
        m.handle(.zoomChanged(factor: 100))
        guard case let .zoom(ctx) = m.state else { Issue.record("expected zoom"); return }
        #expect(ctx.level == 8.0)
    }

    @Test func zoomClampsAtMin() {
        var m = zoomedMachine()
        m.handle(.zoomChanged(factor: 0.01))
        guard case let .zoom(ctx) = m.state else { Issue.record("expected zoom"); return }
        #expect(ctx.level == 1.0)
    }

    @Test func nonFiniteFactorFallsBackToMin() {
        var m = zoomedMachine()
        m.handle(.zoomChanged(factor: .nan))
        guard case let .zoom(ctx) = m.state else { Issue.record("expected zoom"); return }
        #expect(ctx.level == 1.0)
    }

    @Test func mouseMoveUpdatesPanAndRenders() {
        var m = zoomedMachine()
        let p = CGPoint(x: 10, y: 10)
        let fx = m.handle(.mouseMoved(p))
        #expect(fx == [.render])
        guard case let .zoom(ctx) = m.state else { Issue.record("expected zoom"); return }
        #expect(ctx.mouse == p)
    }

    @Test func leftClickEntersDrawOnZoomPreservingContext() {
        var m = zoomedMachine()
        m.handle(.zoomChanged(factor: 2)) // now 4.0
        let fx = m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        #expect(fx == [.render])
        guard case let .draw(ctx) = m.state else { Issue.record("expected draw"); return }
        #expect(ctx.zoom?.level == 4.0)
        #expect(ctx.canvas.color == Settings.default.penColor)
    }

    @Test func drawHotkeyDuringZoomEntersDrawOnZoom() {
        var m = zoomedMachine()
        m.handle(.hotkey(.toggleDraw, mouse: testMouse, screen: testScreen))
        guard case let .draw(ctx) = m.state else { Issue.record("expected draw"); return }
        #expect(ctx.zoom != nil)
    }
}

func drawingMachine() -> SessionStateMachine {
    var m = machine()
    m.handle(.hotkey(.toggleDraw, mouse: testMouse, screen: testScreen))
    return m
}

extension SessionStateMachine {
    var drawContext: DrawContext? {
        switch state {
        case .draw(let ctx): return ctx
        case .type(let ctx, _): return ctx
        default: return nil
        }
    }
}

struct SessionDrawTests {
    let line = Annotation.line(from: .zero, to: CGPoint(x: 5, y: 5), color: .red, width: 4)

    @Test func annotationAddedAppendsAndRenders() {
        var m = drawingMachine()
        let fx = m.handle(.annotationAdded(line))
        #expect(fx == [.render])
        #expect(m.drawContext?.canvas.annotations == [line])
    }

    @Test func colorCommandChangesPenColor() {
        var m = drawingMachine()
        m.handle(.keyCommand(.color(.blue)))
        #expect(m.drawContext?.canvas.color == .blue)
    }

    @Test func undoCommandAndRightClickBothUndo() {
        var m = drawingMachine()
        m.handle(.annotationAdded(line))
        m.handle(.keyCommand(.undo))
        #expect(m.drawContext?.canvas.annotations.isEmpty == true)
        m.handle(.annotationAdded(line))
        m.handle(.rightMouseAction)
        #expect(m.drawContext?.canvas.annotations.isEmpty == true)
    }

    @Test func eraseAllClears() {
        var m = drawingMachine()
        m.handle(.annotationAdded(line))
        m.handle(.keyCommand(.eraseAll))
        #expect(m.drawContext?.canvas.annotations.isEmpty == true)
    }

    @Test func whiteboardTogglesAndBlackboardSwitches() {
        var m = drawingMachine()
        m.handle(.keyCommand(.whiteboard))
        #expect(m.drawContext?.canvas.background == .white)
        m.handle(.keyCommand(.blackboard))
        #expect(m.drawContext?.canvas.background == .black)
        m.handle(.keyCommand(.blackboard))
        #expect(m.drawContext?.canvas.background == .transparent)
    }

    @Test func penWidthDeltaClamps() {
        var m = drawingMachine()
        m.handle(.penWidthChanged(delta: 100))
        #expect(m.drawContext?.canvas.penWidth == 20)
        m.handle(.penWidthChanged(delta: -100))
        #expect(m.drawContext?.canvas.penWidth == 1)
    }

    @Test func saveAndCopyEmitEffectsWithoutStateChange() {
        var m = drawingMachine()
        #expect(m.handle(.keyCommand(.save)) == [.saveScreenshot])
        #expect(m.handle(.keyCommand(.copy)) == [.copyScreenshot])
        #expect(m.drawContext != nil)
    }

    @Test func escFromPlainDrawExits() {
        var m = drawingMachine()
        let fx = m.handle(.escape)
        #expect(fx == [.dismissOverlays])
        #expect(m.state == .idle)
    }

    @Test func escFromDrawOnZoomReturnsToZoom() {
        var m = zoomedMachine()
        m.handle(.leftMouseDown(.zero))
        let fx = m.handle(.escape)
        #expect(fx == [.render])
        guard case .zoom = m.state else { Issue.record("expected zoom"); return }
    }

    @Test func zoomHotkeyDuringDrawExitsToIdle() {
        var m = drawingMachine()
        m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        #expect(m.state == .idle)
    }
}

struct SessionTypeTests {
    @Test func enterTypeClickTypeEscCommitsText() {
        var m = drawingMachine()
        m.handle(.keyCommand(.enterType))
        guard case .type = m.state else { Issue.record("expected type"); return }
        m.handle(.leftMouseDown(CGPoint(x: 50, y: 60)))
        m.handle(.textInput("hi"))
        let fx = m.handle(.escape)
        #expect(fx == [.render])
        guard case let .draw(ctx) = m.state else { Issue.record("expected draw"); return }
        #expect(ctx.canvas.annotations == [.text("hi", at: CGPoint(x: 50, y: 60), color: .red, fontSize: 32)])
    }

    @Test func typingBeforeClickIsIgnored() {
        var m = drawingMachine()
        m.handle(.keyCommand(.enterType))
        m.handle(.textInput("lost"))
        m.handle(.escape)
        guard case let .draw(ctx) = m.state else { Issue.record("expected draw"); return }
        #expect(ctx.canvas.annotations.isEmpty)
    }

    @Test func clickWhileTypingCommitsPreviousRun() {
        var m = drawingMachine()
        m.handle(.keyCommand(.enterType))
        m.handle(.leftMouseDown(.zero))
        m.handle(.textInput("one"))
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        m.handle(.textInput("two"))
        m.handle(.escape)
        guard case let .draw(ctx) = m.state else { Issue.record("expected draw"); return }
        #expect(ctx.canvas.annotations.count == 2)
    }

    @Test func deleteBackwardEdits() {
        var m = drawingMachine()
        m.handle(.keyCommand(.enterType))
        m.handle(.leftMouseDown(.zero))
        m.handle(.textInput("ab"))
        m.handle(.deleteBackward)
        m.handle(.escape)
        guard case let .draw(ctx) = m.state else { Issue.record("expected draw"); return }
        #expect(ctx.canvas.annotations == [.text("a", at: .zero, color: .red, fontSize: 32)])
    }

    @Test func fontSizeCommandsAdjust() {
        var m = drawingMachine()
        m.handle(.keyCommand(.enterType))
        m.handle(.leftMouseDown(.zero))
        m.handle(.keyCommand(.fontIncrease))
        m.handle(.textInput("big"))
        m.handle(.escape)
        guard case let .draw(ctx) = m.state else { Issue.record("expected draw"); return }
        #expect(ctx.canvas.annotations == [.text("big", at: .zero, color: .red, fontSize: 36)])
    }

    @Test func hotkeyDuringTypeCommitsAndExits() {
        var m = drawingMachine()
        m.handle(.keyCommand(.enterType))
        m.handle(.leftMouseDown(.zero))
        m.handle(.textInput("x"))
        let fx = m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        #expect(fx == [.dismissOverlays])
        #expect(m.state == .idle)
    }
}

func breakMachine(_ settings: Settings = .default) -> SessionStateMachine {
    var m = machine(settings)
    m.handle(.breakRequested(now: 1000))
    return m
}

extension SessionStateMachine {
    var breakContext: BreakContext? {
        if case .breakTimer(let ctx) = state { return ctx }
        return nil
    }
}

struct SessionBreakEntryTests {
    @Test func breakRequestedEntersTimerWithSolidBackground() {
        var m = machine() // default background: solidBlack
        let fx = m.handle(.breakRequested(now: 1000))
        #expect(fx == [.showOverlays, .render])
        guard let ctx = m.breakContext else { Issue.record("expected break"); return }
        #expect(ctx.timer.remaining(at: 1000) == 600)
        #expect(!ctx.usedFallbackBackground)
        #expect(!ctx.soundPlayed)
    }

    @Test func fadedDesktopEntersCaptureFirst() {
        var settings = Settings.default
        settings.breakTimer.background = .fadedDesktop
        var m = machine(settings)
        let fx = m.handle(.breakRequested(now: 1000))
        #expect(fx == [.captureScreens])
        #expect(m.state == .capturing(.breakTimer(now: 1000)))
        let fx2 = m.handle(.captureCompleted)
        #expect(fx2 == [.showOverlays, .render])
        #expect(m.breakContext?.usedFallbackBackground == false)
    }

    @Test func captureFailureFallsBackToSolidAndStillStarts() {
        var settings = Settings.default
        settings.breakTimer.background = .fadedDesktop
        for failure in [CaptureFailure.permissionDenied, .captureError] {
            var m = machine(settings)
            m.handle(.breakRequested(now: 1000))
            let fx = m.handle(.captureFailed(failure))
            #expect(fx == [.showOverlays, .render]) // no permission guidance mid-break
            guard let ctx = m.breakContext else { Issue.record("expected break"); return }
            #expect(ctx.usedFallbackBackground)
            #expect(ctx.timer.remaining(at: 1000) == 600)
        }
    }

    @Test func zoomCaptureFailureStillShowsGuidance() {
        var m = machine()
        m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        #expect(m.handle(.captureFailed(.permissionDenied)) == [.showPermissionGuidance])
        #expect(m.state == .idle)
    }

    @Test func exitsOnEscapeRightClickAndToggle() {
        for event in [SessionEvent.escape, .rightMouseAction, .breakRequested(now: 2000)] {
            var m = breakMachine()
            let fx = m.handle(event)
            #expect(fx == [.dismissOverlays])
            #expect(m.state == .idle)
        }
    }

    @Test func otherHotkeysExitBreakToIdle() {
        for action in [HotkeyAction.toggleZoom, .toggleDraw] {
            var m = breakMachine()
            let fx = m.handle(.hotkey(action, mouse: testMouse, screen: testScreen))
            #expect(fx == [.dismissOverlays])
            #expect(m.state == .idle)
        }
    }

    @Test func breakRequestedDuringZoomExitsToIdle() {
        var m = zoomedMachine()
        let fx = m.handle(.breakRequested(now: 1000))
        #expect(fx == [.dismissOverlays])
        #expect(m.state == .idle)
    }

    @Test func breakRequestedDuringTypeCommitsRunThenExits() {
        var m = drawingMachine()
        m.handle(.keyCommand(.enterType))
        m.handle(.leftMouseDown(.zero))
        m.handle(.textInput("x"))
        let fx = m.handle(.breakRequested(now: 1000))
        #expect(fx == [.dismissOverlays])
        #expect(m.state == .idle)
    }

    @Test func defaultBreakHotkeyIsCtrl3() {
        #expect(HotkeyConfiguration.default.combo(for: .toggleBreak) == KeyCombo(keyCode: 20, modifiers: .control))
        #expect(HotkeyConfiguration.default.conflictingCombos().isEmpty)
    }
}

struct SessionBreakRunTests {
    // breakMachine() starts a 600 s timer at now=1000 (defaults: sound on, elapsed on)

    @Test func tickRendersWhileRunning() {
        var m = breakMachine()
        #expect(m.handle(.breakTick(now: 1001)) == [.render])
        #expect(m.breakContext?.soundPlayed == false)
    }

    @Test func expiryEmitsSoundOnceThenKeepsCounting() {
        var m = breakMachine()
        #expect(m.handle(.breakTick(now: 1600)) == [.playExpirySound, .render])
        #expect(m.breakContext?.soundPlayed == true)
        #expect(m.handle(.breakTick(now: 1601)) == [.render]) // once
        guard case .breakTimer = m.state else { Issue.record("still counting elapsed"); return }
    }

    @Test func expiryWithSoundDisabledJustRenders() {
        var settings = Settings.default
        settings.breakTimer.playSound = false
        var m = breakMachine(settings)
        #expect(m.handle(.breakTick(now: 1600)) == [.render])
        #expect(m.breakContext?.soundPlayed == true) // marked so re-eval stops
    }

    @Test func expiryWithoutElapsedDisplayExits() {
        var settings = Settings.default
        settings.breakTimer.showElapsedAfterExpiry = false
        var m = breakMachine(settings)
        let fx = m.handle(.breakTick(now: 1600))
        #expect(fx == [.playExpirySound, .dismissOverlays])
        #expect(m.state == .idle)
    }

    @Test func pauseResumeToggles() {
        var m = breakMachine()
        m.handle(.breakPauseResume(now: 1100)) // pause with 500 left
        #expect(m.breakContext?.timer.isPaused == true)
        m.handle(.breakTick(now: 5000))
        #expect(m.breakContext?.timer.remaining(at: 5000) == 500)
        m.handle(.breakPauseResume(now: 5000)) // resume
        #expect(m.breakContext?.timer.isPaused == false)
        #expect(m.breakContext?.timer.remaining(at: 5100) == 400)
    }

    @Test func adjustChangesRemaining() {
        var m = breakMachine()
        #expect(m.handle(.breakAdjust(seconds: 60, now: 1000)) == [.render])
        #expect(m.breakContext?.timer.remaining(at: 1000) == 660)
        m.handle(.breakAdjust(seconds: -60, now: 1000))
        #expect(m.breakContext?.timer.remaining(at: 1000) == 600)
    }

    @Test func adjustAfterExpiryRearmsSound() {
        var m = breakMachine()
        m.handle(.breakTick(now: 1600)) // expire, sound played
        m.handle(.breakAdjust(seconds: 60, now: 1600))
        #expect(m.breakContext?.soundPlayed == false) // re-armed
        #expect(m.handle(.breakTick(now: 1660)) == [.playExpirySound, .render])
    }

    @Test func breakEventsIgnoredOutsideBreakState() {
        var m = machine()
        #expect(m.handle(.breakTick(now: 1)).isEmpty)
        #expect(m.handle(.breakPauseResume(now: 1)).isEmpty)
        #expect(m.handle(.breakAdjust(seconds: 60, now: 1)).isEmpty)
    }

    @Test func pauseIgnoredAfterExpiry() {
        var m = breakMachine()
        m.handle(.breakTick(now: 1600)) // expired
        #expect(m.handle(.breakPauseResume(now: 1700)).isEmpty)
        #expect(m.breakContext?.timer.isPaused == false)
        #expect(m.breakContext?.timer.elapsedAfterExpiry(at: 1700) == 100)
    }

    @Test func expiryWithSoundOffAndElapsedOffJustDismisses() {
        var settings = Settings.default
        settings.breakTimer.playSound = false
        settings.breakTimer.showElapsedAfterExpiry = false
        var m = breakMachine(settings)
        #expect(m.handle(.breakTick(now: 1600)) == [.dismissOverlays])
        #expect(m.state == .idle)
    }
}

func liveZoomMachine(_ settings: Settings = .default) -> SessionStateMachine {
    var m = machine(settings)
    m.handle(.hotkey(.toggleLiveZoom, mouse: testMouse, screen: testScreen))
    return m
}

struct SessionLiveZoomTests {
    @Test func hotkeyEntersLiveZoomImmediately() {
        var m = machine()
        let fx = m.handle(.hotkey(.toggleLiveZoom, mouse: testMouse, screen: testScreen))
        #expect(fx == [.showOverlays, .startLiveStream, .render])
        #expect(m.state == .liveZoom(ZoomContext(level: 2.0, mouse: testMouse, screen: testScreen)))
    }

    @Test func defaultLiveZoomHotkeyIsCtrl4AndConflictFree() {
        #expect(HotkeyConfiguration.default.combo(for: .toggleLiveZoom) == KeyCombo(keyCode: 21, modifiers: .control))
        #expect(HotkeyConfiguration.default.conflictingCombos().isEmpty)
    }

    @Test func zoomAndPanMirrorFrozenZoom() {
        var m = liveZoomMachine()
        #expect(m.handle(.zoomChanged(factor: 2)) == [.render])
        guard case .liveZoom(let ctx) = m.state else { Issue.record("expected liveZoom"); return }
        #expect(ctx.level == 4.0)
        #expect(m.handle(.mouseMoved(CGPoint(x: 5, y: 5))) == [.render])
        guard case .liveZoom(let ctx2) = m.state else { Issue.record("expected liveZoom"); return }
        #expect(ctx2.mouse == CGPoint(x: 5, y: 5))
    }

    @Test func zoomClampsAtBounds() {
        var m = liveZoomMachine()
        m.handle(.zoomChanged(factor: 100))
        guard case .liveZoom(let ctx) = m.state else { Issue.record("expected liveZoom"); return }
        #expect(ctx.level == 8.0)
        m.handle(.zoomChanged(factor: 0.001))
        guard case .liveZoom(let ctx2) = m.state else { Issue.record("expected liveZoom"); return }
        #expect(ctx2.level == 1.0)
    }

    @Test func exitsStopStreamThenDismiss() {
        for event in [SessionEvent.escape, .rightMouseAction,
                      .hotkey(.toggleLiveZoom, mouse: testMouse, screen: testScreen),
                      .hotkey(.toggleZoom, mouse: testMouse, screen: testScreen),
                      .hotkey(.toggleBreak, mouse: testMouse, screen: testScreen),
                      .breakRequested(now: 1)] {
            var m = liveZoomMachine()
            let fx = m.handle(event)
            #expect(fx == [.stopLiveStream, .dismissOverlays])
            #expect(m.state == .idle)
        }
    }

    @Test func displayChangeStopsStream() {
        var m = liveZoomMachine()
        let fx = m.handle(.displayConfigurationChanged)
        #expect(fx == [.stopLiveStream, .dismissOverlays])
        #expect(m.state == .idle)
        var z = zoomedMachine() // non-live states keep the old shape
        #expect(z.handle(.displayConfigurationChanged) == [.dismissOverlays])
    }

    @Test func streamFailureRoutesByReason() {
        var m = liveZoomMachine()
        #expect(m.handle(.liveStreamFailed(.permissionDenied)) == [.stopLiveStream, .dismissOverlays, .showPermissionGuidance])
        #expect(m.state == .idle)
        var m2 = liveZoomMachine()
        #expect(m2.handle(.liveStreamFailed(.captureError)) == [.stopLiveStream, .dismissOverlays, .notifyCaptureFailure])
        #expect(m2.state == .idle)
    }

    @Test func liveEventsIgnoredOutsideLiveZoom() {
        var m = machine()
        #expect(m.handle(.liveFrameFrozen).isEmpty)
        #expect(m.handle(.liveStreamFailed(.captureError)).isEmpty)
        var d = drawingMachine()
        #expect(d.handle(.liveFrameFrozen).isEmpty)
    }

    @Test func liveZoomHotkeyDuringOtherModesExitsToIdle() {
        var z = zoomedMachine()
        #expect(z.handle(.hotkey(.toggleLiveZoom, mouse: testMouse, screen: testScreen)) == [.dismissOverlays])
        #expect(z.state == .idle)
        var b = breakMachine()
        #expect(b.handle(.hotkey(.toggleLiveZoom, mouse: testMouse, screen: testScreen)) == [.dismissOverlays])
        #expect(b.state == .idle)
    }
}
