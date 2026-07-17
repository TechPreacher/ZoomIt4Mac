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

    @Test func liveZoomHotkeyDuringDrawExitsToIdle() {
        var m = drawingMachine()
        #expect(m.handle(.hotkey(.toggleLiveZoom, mouse: testMouse, screen: testScreen)) == [.dismissOverlays])
        #expect(m.state == .idle)
    }

    @Test func liveZoomHotkeyDuringTypeCommitsAndExits() {
        var m = drawingMachine()
        m.handle(.keyCommand(.enterType))
        m.handle(.leftMouseDown(.zero))
        m.handle(.textInput("x"))
        let fx = m.handle(.hotkey(.toggleLiveZoom, mouse: testMouse, screen: testScreen))
        #expect(fx == [.dismissOverlays])
        #expect(m.state == .idle)
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

struct SessionLiveZoomFreezeTests {
    @Test func clickRequestsFreezeWithoutStateChange() {
        var m = liveZoomMachine()
        let fx = m.handle(.leftMouseDown(.zero))
        #expect(fx == [.freezeLiveFrame])
        guard case .liveZoom = m.state else { Issue.record("state must not change yet"); return }
    }

    @Test func drawHotkeyAlsoRequestsFreeze() {
        var m = liveZoomMachine()
        #expect(m.handle(.hotkey(.toggleDraw, mouse: testMouse, screen: testScreen)) == [.freezeLiveFrame])
    }

    @Test func frozenFrameEntersDrawFromLive() {
        var m = liveZoomMachine()
        m.handle(.zoomChanged(factor: 2)) // 4.0
        m.handle(.leftMouseDown(.zero))
        let fx = m.handle(.liveFrameFrozen)
        #expect(fx == [.stopLiveStream, .render])
        guard case .draw(let ctx) = m.state else { Issue.record("expected draw"); return }
        #expect(ctx.fromLiveZoom)
        #expect(ctx.zoom?.level == 4.0)
        #expect(ctx.canvas.color == Settings.default.penColor)
    }

    @Test func escFromLiveDrawReturnsToLiveZoom() {
        var m = liveZoomMachine()
        m.handle(.leftMouseDown(.zero))
        m.handle(.liveFrameFrozen)
        let fx = m.handle(.escape)
        #expect(fx == [.startLiveStream, .render])
        guard case .liveZoom(let ctx) = m.state else { Issue.record("expected liveZoom"); return }
        #expect(ctx.level == 2.0)
    }

    @Test func escFromFrozenZoomDrawStillReturnsToFrozenZoom() {
        var m = zoomedMachine()
        m.handle(.leftMouseDown(.zero))
        let fx = m.handle(.escape)
        #expect(fx == [.render]) // no startLiveStream for the frozen path
        guard case .zoom = m.state else { Issue.record("expected zoom"); return }
    }

    @Test func liveDrawOtherExitsUnaffected() {
        var m = liveZoomMachine()
        m.handle(.leftMouseDown(.zero))
        m.handle(.liveFrameFrozen)
        // toggleZoom exits to idle, not back to live
        let fx = m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        #expect(fx == [.dismissOverlays])
        #expect(m.state == .idle)
    }
}

/// Toggle ⌃5 and let the notice elapse so capture is actually running.
func recordingMachine(_ base: SessionStateMachine = machine()) -> SessionStateMachine {
    var m = base
    m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
    m.handle(.recordingNoticeElapsed)
    return m
}

/// ⌃⇧5 through capture into .record snip selection.
func regionSelectionMachine(_ base: SessionStateMachine = machine()) -> SessionStateMachine {
    var m = base
    m.handle(.hotkey(.regionRecord, mouse: testMouse, screen: testScreen))
    m.handle(.captureCompleted)
    return m
}

struct SessionRecordingTests {
    @Test func toggleShowsNoticeThenElapsedStarts() {
        var m = machine()
        #expect(m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen)) == [.showRecordingNotice])
        #expect(m.recordingPhase == .pending(region: nil))
        #expect(!m.isRecording) // capture not running during the notice
        #expect(m.state == .idle) // no mode entered
        #expect(m.handle(.recordingNoticeElapsed) == [.dismissRecordingNotice, .startRecording(region: nil)])
        #expect(m.isRecording)
        #expect(m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen)) == [.stopRecording])
        #expect(m.recordingPhase == .off)
    }

    @Test func secondToggleDuringNoticeCancels() {
        var m = machine()
        m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
        #expect(m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen)) == [.dismissRecordingNotice])
        #expect(m.recordingPhase == .off)
        // A late timer tick after cancellation must not start anything.
        #expect(m.handle(.recordingNoticeElapsed).isEmpty)
        #expect(!m.isRecording)
    }

    @Test func noticeElapsedIgnoredWhenNotPending() {
        var m = machine()
        #expect(m.handle(.recordingNoticeElapsed).isEmpty)
        var active = recordingMachine()
        #expect(active.handle(.recordingNoticeElapsed).isEmpty) // already active
    }

    @Test func toggleDoesNotDisturbActiveModes() {
        var zoom = zoomedMachine()
        #expect(zoom.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen)) == [.showRecordingNotice])
        guard case .zoom = zoom.state else { Issue.record("zoom must survive"); return }

        var draw = drawingMachine()
        draw.handle(.annotationAdded(.line(from: .zero, to: CGPoint(x: 5, y: 5), color: .red, width: 4)))
        draw = recordingMachine(draw)
        #expect(draw.isRecording)
        #expect(draw.drawContext?.canvas.annotations.count == 1) // context preserved

        var brk = recordingMachine(breakMachine())
        #expect(brk.isRecording)
        guard case .breakTimer = brk.state else { Issue.record("break must survive"); return }

        var live = recordingMachine(liveZoomMachine())
        #expect(live.isRecording)
        guard case .liveZoom = live.state else { Issue.record("live zoom must survive"); return }
    }

    @Test func modeChangesLeaveRecordingOn() {
        var m = recordingMachine()
        m.handle(.hotkey(.toggleDraw, mouse: testMouse, screen: testScreen)) // enter draw
        #expect(m.isRecording)
        m.handle(.escape) // exit draw
        #expect(m.isRecording)
        #expect(m.state == .idle)
        m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        m.handle(.captureCompleted) // enter zoom
        #expect(m.isRecording)
        m.handle(.escape)
        #expect(m.isRecording)
    }

    @Test func recordingFailedClearsOnlyWhenActive() {
        var m = machine()
        #expect(m.handle(.recordingFailed).isEmpty)
        m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
        #expect(m.handle(.recordingFailed).isEmpty) // pending: nothing to fail yet
        m.handle(.recordingNoticeElapsed)
        #expect(m.handle(.recordingFailed) == [.notifyCaptureFailure])
        #expect(!m.isRecording)
        #expect(m.handle(.recordingFailed).isEmpty) // idempotent
    }

    @Test func displayChangeStopsRecordingAndExitsMode() {
        var m = recordingMachine(zoomedMachine())
        let fx = m.handle(.displayConfigurationChanged)
        #expect(fx == [.stopRecording, .dismissOverlays])
        #expect(!m.isRecording)
        #expect(m.state == .idle)
    }

    @Test func displayChangeDuringNoticeCancelsIt() {
        var m = machine()
        m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
        #expect(m.handle(.displayConfigurationChanged) == [.dismissRecordingNotice])
        #expect(m.recordingPhase == .off)
    }

    @Test func displayChangeInIdleWhileRecordingJustStops() {
        var m = recordingMachine()
        #expect(m.handle(.displayConfigurationChanged) == [.stopRecording])
        #expect(!m.isRecording)
    }

    @Test func displayChangeDuringLiveZoomWhileRecordingOrdersEffects() {
        var m = recordingMachine(liveZoomMachine())
        #expect(m.handle(.displayConfigurationChanged) == [.stopRecording, .stopLiveStream, .dismissOverlays])
    }

    @Test func recordHotkeyDoesNotCommitOrExitType() {
        var m = drawingMachine()
        m.handle(.keyCommand(.enterType))
        m.handle(.leftMouseDown(.zero))
        m.handle(.textInput("hi"))
        m = recordingMachine(m)
        #expect(m.isRecording)
        guard case .type = m.state else { Issue.record("type must survive"); return }
    }

    @Test func toggleDuringCaptureLeavesCaptureIntact() {
        var m = machine()
        m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen)) // .capturing
        #expect(m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen)) == [.showRecordingNotice])
        m.handle(.recordingNoticeElapsed)
        #expect(m.isRecording)
        guard case .capturing = m.state else { Issue.record("capturing must survive"); return }
    }

    @Test func settingsChangedPreservesRecording() {
        var m = recordingMachine()
        m.handle(.settingsChanged(Settings.default))
        #expect(m.isRecording)
    }
}

struct SnipSessionTests {
    private func machine() -> SessionStateMachine {
        SessionStateMachine(settings: .default)
    }

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)

    /// A machine already sitting in .snip with no selection started.
    private func snipMachine() -> SessionStateMachine {
        var m = machine()
        m.handle(.hotkey(.snip, mouse: CGPoint(x: 1, y: 1), screen: screen))
        m.handle(.captureCompleted)
        return m
    }

    // MARK: entry

    @Test func snipHotkeyStartsCapture() {
        var m = machine()
        let effects = m.handle(.hotkey(.snip, mouse: CGPoint(x: 1, y: 1), screen: screen))
        #expect(m.state == .capturing(.snip))
        #expect(effects == [.captureScreens])
    }

    @Test func captureCompletedEntersSnip() {
        var m = machine()
        m.handle(.hotkey(.snip, mouse: .zero, screen: screen))
        let effects = m.handle(.captureCompleted)
        #expect(m.state == .snip(SnipContext()))
        #expect(effects == [.showOverlays, .render])
    }

    @Test func capturePermissionFailureShowsGuidance() {
        var m = machine()
        m.handle(.hotkey(.snip, mouse: .zero, screen: screen))
        let effects = m.handle(.captureFailed(.permissionDenied))
        #expect(m.state == .idle)
        #expect(effects == [.showPermissionGuidance])
    }

    @Test func captureErrorNotifies() {
        var m = machine()
        m.handle(.hotkey(.snip, mouse: .zero, screen: screen))
        let effects = m.handle(.captureFailed(.captureError))
        #expect(m.state == .idle)
        #expect(effects == [.notifyCaptureFailure])
    }

    @Test func escapeDuringCaptureAborts() {
        var m = machine()
        m.handle(.hotkey(.snip, mouse: .zero, screen: screen))
        let effects = m.handle(.escape)
        #expect(m.state == .idle)
        #expect(effects == [])
    }

    // MARK: selection lifecycle

    @Test func mouseDownAnchorsSelection() {
        var m = snipMachine()
        let effects = m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        #expect(m.state == .snip(SnipContext(anchor: CGPoint(x: 100, y: 100), current: CGPoint(x: 100, y: 100))))
        #expect(effects == [.render])
    }

    @Test func mouseMovedUpdatesCurrentOnlyWhileDragging() {
        var m = snipMachine()
        #expect(m.handle(.mouseMoved(CGPoint(x: 5, y: 5))) == [])
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        let effects = m.handle(.mouseMoved(CGPoint(x: 250, y: 180)))
        #expect(m.state == .snip(SnipContext(anchor: CGPoint(x: 100, y: 100), current: CGPoint(x: 250, y: 180))))
        #expect(effects == [.render])
    }

    @Test func mouseUpExportsNormalizedSelectionThenDismisses() {
        var m = snipMachine()
        m.handle(.leftMouseDown(CGPoint(x: 300, y: 200)))
        m.handle(.mouseMoved(CGPoint(x: 150, y: 260)))
        let effects = m.handle(.leftMouseUp(CGPoint(x: 100, y: 300), optionHeld: false))
        #expect(m.state == .idle)
        // Export MUST precede dismissOverlays: dismiss clears the snapshot
        // store the crop reads from.
        #expect(effects == [
            .exportSnip(selection: CGRect(x: 100, y: 200, width: 200, height: 100), alsoSave: false),
            .dismissOverlays,
        ])
    }

    @Test func optionHeldRequestsSave() {
        var m = snipMachine()
        m.handle(.leftMouseDown(CGPoint(x: 0, y: 0)))
        let effects = m.handle(.leftMouseUp(CGPoint(x: 50, y: 50), optionHeld: true))
        #expect(effects == [
            .exportSnip(selection: CGRect(x: 0, y: 0, width: 50, height: 50), alsoSave: true),
            .dismissOverlays,
        ])
    }

    @Test func tinyReleaseClearsSelectionAndStays() {
        var m = snipMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        let effects = m.handle(.leftMouseUp(CGPoint(x: 102, y: 102), optionHeld: false))
        #expect(m.state == .snip(SnipContext()))
        #expect(effects == [.render])
    }

    @Test func mouseUpWithoutAnchorIgnored() {
        var m = snipMachine()
        let effects = m.handle(.leftMouseUp(CGPoint(x: 50, y: 50), optionHeld: false))
        #expect(m.state == .snip(SnipContext()))
        #expect(effects == [])
    }

    @Test func mouseUpIgnoredOutsideSnip() {
        var m = machine()
        #expect(m.handle(.leftMouseUp(CGPoint(x: 50, y: 50), optionHeld: false)) == [])
        #expect(m.state == .idle)
    }

    // MARK: cancels

    @Test func escapeCancelsSnip() {
        var m = snipMachine()
        m.handle(.leftMouseDown(CGPoint(x: 10, y: 10)))
        let effects = m.handle(.escape)
        #expect(m.state == .idle)
        #expect(effects == [.dismissOverlays])
    }

    @Test func rightClickCancelsSnip() {
        var m = snipMachine()
        let effects = m.handle(.rightMouseAction)
        #expect(m.state == .idle)
        #expect(effects == [.dismissOverlays])
    }

    @Test func snipHotkeyAgainCancels() {
        var m = snipMachine()
        let effects = m.handle(.hotkey(.snip, mouse: .zero, screen: screen))
        #expect(m.state == .idle)
        #expect(effects == [.dismissOverlays])
    }

    @Test func otherModeHotkeyCancelsSnip() {
        var m = snipMachine()
        let effects = m.handle(.hotkey(.toggleZoom, mouse: .zero, screen: screen))
        #expect(m.state == .idle)
        #expect(effects == [.dismissOverlays])
    }

    @Test func breakRequestCancelsSnip() {
        var m = snipMachine()
        let effects = m.handle(.breakRequested(now: 100))
        #expect(m.state == .idle)
        #expect(effects == [.dismissOverlays])
    }

    @Test func displayChangeCancelsSnip() {
        var m = snipMachine()
        let effects = m.handle(.displayConfigurationChanged)
        #expect(m.state == .idle)
        #expect(effects == [.dismissOverlays])
    }

    // MARK: interaction with other modes and recording

    @Test func snipHotkeyExitsZoom() {
        var m = machine()
        m.handle(.hotkey(.toggleZoom, mouse: .zero, screen: screen))
        m.handle(.captureCompleted)
        let effects = m.handle(.hotkey(.snip, mouse: .zero, screen: screen))
        #expect(m.state == .idle)
        #expect(effects == [.dismissOverlays])
    }

    @Test func snipHotkeyExitsLiveZoom() {
        var m = machine()
        m.handle(.hotkey(.toggleLiveZoom, mouse: .zero, screen: screen))
        let effects = m.handle(.hotkey(.snip, mouse: .zero, screen: screen))
        #expect(m.state == .idle)
        #expect(effects == [.stopLiveStream, .dismissOverlays])
    }

    @Test func snipHotkeyExitsDraw() {
        var m = machine()
        m.handle(.hotkey(.toggleDraw, mouse: .zero, screen: screen))
        let effects = m.handle(.hotkey(.snip, mouse: .zero, screen: screen))
        #expect(m.state == .idle)
        #expect(effects == [.dismissOverlays])
    }

    @Test func snipHotkeyExitsType() {
        var m = machine()
        m.handle(.hotkey(.toggleDraw, mouse: .zero, screen: screen))
        m.handle(.keyCommand(.enterType))
        let effects = m.handle(.hotkey(.snip, mouse: .zero, screen: screen))
        #expect(m.state == .idle)
        #expect(effects == [.dismissOverlays])
    }

    @Test func snipHotkeyExitsBreak() {
        var m = machine()
        m.handle(.breakRequested(now: 100))
        let effects = m.handle(.hotkey(.snip, mouse: .zero, screen: screen))
        #expect(m.state == .idle)
        #expect(effects == [.dismissOverlays])
    }

    @Test func recordingToggleDuringSnipLeavesSnipAlone() {
        var m = snipMachine()
        m.handle(.leftMouseDown(CGPoint(x: 10, y: 10)))
        let before = m.state
        let effects = m.handle(.hotkey(.toggleRecord, mouse: .zero, screen: screen))
        #expect(m.state == before)
        #expect(m.recordingPhase == .pending(region: nil))
        #expect(effects == [.showRecordingNotice])
    }

    @Test func snipEventsLeaveRecordingUntouched() {
        var m = machine()
        m.handle(.hotkey(.toggleRecord, mouse: .zero, screen: screen))
        m.handle(.recordingNoticeElapsed) // recording now active
        m.handle(.hotkey(.snip, mouse: .zero, screen: screen))
        m.handle(.captureCompleted)
        m.handle(.leftMouseDown(CGPoint(x: 0, y: 0)))
        m.handle(.leftMouseUp(CGPoint(x: 100, y: 100), optionHeld: false))
        #expect(m.isRecording)
    }

    // MARK: text snip (OCR)

    @Test func ocrSnipHotkeyStartsCapture() {
        var m = machine()
        let effects = m.handle(.hotkey(.ocrSnip, mouse: .zero, screen: screen))
        #expect(m.state == .capturing(.ocrSnip))
        #expect(effects == [.captureScreens])
    }

    @Test func captureCompletedEntersTextSnip() {
        var m = machine()
        m.handle(.hotkey(.ocrSnip, mouse: .zero, screen: screen))
        let effects = m.handle(.captureCompleted)
        #expect(m.state == .snip(SnipContext(kind: .text)))
        #expect(effects == [.showOverlays, .render])
    }

    @Test func textSnipMouseUpEmitsRecognizeText() {
        var m = machine()
        m.handle(.hotkey(.ocrSnip, mouse: .zero, screen: screen))
        m.handle(.captureCompleted)
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        m.handle(.mouseMoved(CGPoint(x: 300, y: 250)))
        let effects = m.handle(.leftMouseUp(CGPoint(x: 300, y: 250), optionHeld: false))
        #expect(m.state == .idle)
        #expect(effects == [
            .recognizeText(selection: CGRect(x: 100, y: 100, width: 200, height: 150)),
            .dismissOverlays,
        ])
    }

    @Test func textSnipIgnoresOptionOnRelease() {
        var m = machine()
        m.handle(.hotkey(.ocrSnip, mouse: .zero, screen: screen))
        m.handle(.captureCompleted)
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        let effects = m.handle(.leftMouseUp(CGPoint(x: 300, y: 250), optionHeld: true))
        #expect(effects == [
            .recognizeText(selection: CGRect(x: 100, y: 100, width: 200, height: 150)),
            .dismissOverlays,
        ])
    }

    @Test func textSnipInvalidSelectionRetryPreservesKind() {
        var m = machine()
        m.handle(.hotkey(.ocrSnip, mouse: .zero, screen: screen))
        m.handle(.captureCompleted)
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        // Sub-minimum drag (<4pt edge): clears the drag but stays in TEXT snip.
        let effects = m.handle(.leftMouseUp(CGPoint(x: 102, y: 101), optionHeld: false))
        #expect(m.state == .snip(SnipContext(kind: .text)))
        #expect(effects == [.render])
    }

    @Test func ocrSnipCaptureFailureRoutesLikeSnip() {
        var m = machine()
        m.handle(.hotkey(.ocrSnip, mouse: .zero, screen: screen))
        let effects = m.handle(.captureFailed(.permissionDenied))
        #expect(m.state == .idle)
        #expect(effects == [.showPermissionGuidance])

        var m2 = machine()
        m2.handle(.hotkey(.ocrSnip, mouse: .zero, screen: screen))
        let effects2 = m2.handle(.captureFailed(.captureError))
        #expect(m2.state == .idle)
        #expect(effects2 == [.notifyCaptureFailure])
    }
}

struct PenStyleTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)

    /// Plain draw (no zoom context, no snapshot).
    private func plainDraw() -> SessionStateMachine {
        var m = SessionStateMachine(settings: .default)
        m.handle(.hotkey(.toggleDraw, mouse: .zero, screen: screen))
        return m
    }

    /// Draw on a frozen zoom (zoom context present).
    private func zoomDraw() -> SessionStateMachine {
        var m = SessionStateMachine(settings: .default)
        m.handle(.hotkey(.toggleZoom, mouse: CGPoint(x: 1, y: 1), screen: screen))
        m.handle(.captureCompleted)
        m.handle(.leftMouseDown(CGPoint(x: 1, y: 1)))
        return m
    }

    private func canvas(_ m: SessionStateMachine) -> AnnotationCanvas? {
        if case .draw(let ctx) = m.state { return ctx.canvas }
        return nil
    }

    @Test func defaultStyleIsNormal() {
        #expect(canvas(plainDraw())?.penStyle == .normal)
    }

    @Test func highlighterTogglesOnAndOff() {
        var m = plainDraw()
        #expect(m.handle(.keyCommand(.toggleHighlighter)) == [.render])
        #expect(canvas(m)?.penStyle == .highlighter)
        #expect(m.handle(.keyCommand(.toggleHighlighter)) == [.render])
        #expect(canvas(m)?.penStyle == .normal)
    }

    @Test func blurTogglesInZoomBackedDraw() {
        var m = zoomDraw()
        #expect(m.handle(.keyCommand(.toggleBlur)) == [.render])
        #expect(canvas(m)?.penStyle == .blur)
        #expect(m.handle(.keyCommand(.toggleBlur)) == [.render])
        #expect(canvas(m)?.penStyle == .normal)
    }

    @Test func blurRefusedInPlainDraw() {
        var m = plainDraw()
        #expect(m.handle(.keyCommand(.toggleBlur)) == [.notifyCaptureFailure])
        #expect(canvas(m)?.penStyle == .normal)
    }

    @Test func highlighterSwitchesDirectlyToBlur() {
        var m = zoomDraw()
        m.handle(.keyCommand(.toggleHighlighter))
        m.handle(.keyCommand(.toggleBlur))
        #expect(canvas(m)?.penStyle == .blur)
    }

    @Test func colorKeyRevertsStyleToNormalAndSetsColor() {
        var m = zoomDraw()
        m.handle(.keyCommand(.toggleBlur))
        #expect(m.handle(.keyCommand(.color(.green))) == [.render])
        #expect(canvas(m)?.penStyle == .normal)
        #expect(canvas(m)?.color == .green)
    }

    @Test func boardRevertsBlurButNotHighlighter() {
        var m = zoomDraw()
        m.handle(.keyCommand(.toggleBlur))
        m.handle(.keyCommand(.whiteboard))
        #expect(canvas(m)?.penStyle == .normal)

        var h = zoomDraw()
        h.handle(.keyCommand(.toggleHighlighter))
        h.handle(.keyCommand(.blackboard))
        #expect(canvas(h)?.penStyle == .highlighter)
    }

    @Test func styleSurvivesTypeRoundTrip() {
        var m = zoomDraw()
        m.handle(.keyCommand(.toggleHighlighter))
        m.handle(.keyCommand(.enterType))
        m.handle(.escape)
        #expect(canvas(m)?.penStyle == .highlighter)
    }

    @Test func blurAllowedInDrawFromFrozenLiveZoom() {
        var m = SessionStateMachine(settings: .default)
        m.handle(.hotkey(.toggleLiveZoom, mouse: CGPoint(x: 1, y: 1), screen: screen))
        m.handle(.leftMouseDown(CGPoint(x: 1, y: 1)))
        m.handle(.liveFrameFrozen)
        #expect(m.handle(.keyCommand(.toggleBlur)) == [.render])
        #expect(canvas(m)?.penStyle == .blur)
    }
}

struct RegionRecordingTests {
    @Test func regionHotkeyStartsSelectionCapture() {
        var m = machine()
        #expect(m.handle(.hotkey(.regionRecord, mouse: testMouse, screen: testScreen)) == [.captureScreens])
        #expect(m.state == .capturing(.regionRecord))
        #expect(m.recordingPhase == .off)
    }

    @Test func captureCompletedEntersRecordSnip() {
        var m = machine()
        m.handle(.hotkey(.regionRecord, mouse: testMouse, screen: testScreen))
        #expect(m.handle(.captureCompleted) == [.showOverlays, .render])
        #expect(m.state == .snip(SnipContext(kind: .record)))
    }

    @Test func releaseShowsNoticeCarryingRegion() {
        var m = regionSelectionMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        let fx = m.handle(.leftMouseUp(CGPoint(x: 300, y: 250), optionHeld: false))
        #expect(fx == [.dismissOverlays, .showRecordingNotice])
        #expect(m.state == .idle)
        #expect(m.recordingPhase == .pending(region: CGRect(x: 100, y: 100, width: 200, height: 150)))
        #expect(!m.isRecording)
    }

    @Test func noticeElapsedStartsRegionRecording() {
        var m = regionSelectionMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        m.handle(.leftMouseUp(CGPoint(x: 300, y: 250), optionHeld: false))
        let fx = m.handle(.recordingNoticeElapsed)
        #expect(fx == [.dismissRecordingNotice, .startRecording(region: CGRect(x: 100, y: 100, width: 200, height: 150))])
        #expect(m.isRecording)
    }

    @Test func regionHotkeyDuringNoticeCancels() {
        var m = regionSelectionMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        m.handle(.leftMouseUp(CGPoint(x: 300, y: 250), optionHeld: false))
        #expect(m.handle(.hotkey(.regionRecord, mouse: testMouse, screen: testScreen)) == [.dismissRecordingNotice])
        #expect(m.recordingPhase == .off)
        #expect(m.handle(.recordingNoticeElapsed).isEmpty)
    }

    @Test func regionHotkeyWhileActiveStops() {
        var m = regionSelectionMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        m.handle(.leftMouseUp(CGPoint(x: 300, y: 250), optionHeld: false))
        m.handle(.recordingNoticeElapsed)
        #expect(m.handle(.hotkey(.regionRecord, mouse: testMouse, screen: testScreen)) == [.stopRecording])
        #expect(m.recordingPhase == .off)
    }

    @Test func toggleRecordStopsRegionRecording() {
        var m = regionSelectionMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        m.handle(.leftMouseUp(CGPoint(x: 300, y: 250), optionHeld: false))
        m.handle(.recordingNoticeElapsed)
        #expect(m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen)) == [.stopRecording])
        #expect(!m.isRecording)
    }

    @Test func subMinimumDragRetriesPreservingRecordKind() {
        var m = regionSelectionMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        // 31pt: over the 4pt snip minimum, under the 32pt recording minimum.
        let fx = m.handle(.leftMouseUp(CGPoint(x: 131, y: 131), optionHeld: false))
        #expect(fx == [.render])
        #expect(m.state == .snip(SnipContext(kind: .record)))
        #expect(m.recordingPhase == .off)
    }

    @Test func escapeDuringSelectionCancelsCleanly() {
        var m = regionSelectionMachine()
        #expect(m.handle(.escape) == [.dismissOverlays])
        #expect(m.state == .idle)
        #expect(m.recordingPhase == .off)
    }

    @Test func fullDisplayRecordingStillCarriesNilRegion() {
        var m = machine()
        #expect(m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen)) == [.showRecordingNotice])
        #expect(m.recordingPhase == .pending(region: nil))
        #expect(m.handle(.recordingNoticeElapsed) == [.dismissRecordingNotice, .startRecording(region: nil)])
    }

    @Test func regionCaptureFailureRoutesLikeSnip() {
        var m = machine()
        m.handle(.hotkey(.regionRecord, mouse: testMouse, screen: testScreen))
        #expect(m.handle(.captureFailed(.permissionDenied)) == [.showPermissionGuidance])
        #expect(m.state == .idle)
        #expect(m.recordingPhase == .off)
    }
}
