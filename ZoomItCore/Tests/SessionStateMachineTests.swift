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
        #expect(m.state == .capturing(mouse: testMouse, screen: testScreen))
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
