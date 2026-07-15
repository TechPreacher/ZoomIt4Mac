import CoreGraphics
import Foundation

public struct ZoomContext: Equatable, Sendable {
    public var level: CGFloat
    public var mouse: CGPoint
    public var screen: CGRect

    public init(level: CGFloat, mouse: CGPoint, screen: CGRect) {
        self.level = level
        self.mouse = mouse
        self.screen = screen
    }
}

public struct DrawContext: Equatable, Sendable {
    public var canvas: AnnotationCanvas
    public var zoom: ZoomContext?
    public var fromLiveZoom: Bool

    public init(canvas: AnnotationCanvas, zoom: ZoomContext?, fromLiveZoom: Bool = false) {
        self.canvas = canvas
        self.zoom = zoom
        self.fromLiveZoom = fromLiveZoom
    }
}

public enum CaptureFailure: Error, Equatable, Sendable {
    case permissionDenied, captureError
}

public enum CaptureTarget: Equatable, Sendable {
    case zoom(mouse: CGPoint, screen: CGRect)
    case breakTimer(now: TimeInterval)
}

public struct BreakContext: Equatable, Sendable {
    public var timer: BreakTimer
    public var soundPlayed: Bool
    public var usedFallbackBackground: Bool

    public init(timer: BreakTimer, soundPlayed: Bool = false, usedFallbackBackground: Bool = false) {
        self.timer = timer
        self.soundPlayed = soundPlayed
        self.usedFallbackBackground = usedFallbackBackground
    }
}

public enum SessionState: Equatable, Sendable {
    case idle
    case capturing(CaptureTarget)
    case zoom(ZoomContext)
    case liveZoom(ZoomContext)
    case draw(DrawContext)
    case type(DrawContext, TypeTool)
    case breakTimer(BreakContext)
}

public enum KeyCommand: Equatable, Sendable {
    case color(AnnotationColor)
    case undo, eraseAll, whiteboard, blackboard, enterType
    case save, copy
    case fontIncrease, fontDecrease
}

public enum SessionEvent: Equatable, Sendable {
    case hotkey(HotkeyAction, mouse: CGPoint, screen: CGRect)
    case captureCompleted
    case captureFailed(CaptureFailure)
    case escape
    case leftMouseDown(CGPoint)
    case rightMouseAction
    case zoomChanged(factor: CGFloat)
    case mouseMoved(CGPoint)
    case keyCommand(KeyCommand)
    case annotationAdded(Annotation)
    case penWidthChanged(delta: CGFloat)
    case textInput(String)
    case deleteBackward
    case displayConfigurationChanged
    case settingsChanged(Settings)
    case breakRequested(now: TimeInterval)
    case breakTick(now: TimeInterval)
    case breakPauseResume(now: TimeInterval)
    case breakAdjust(seconds: TimeInterval, now: TimeInterval)
    case liveFrameFrozen
    case liveStreamFailed(CaptureFailure)
    case recordingFailed
    case recordingNoticeElapsed
}

public enum SessionEffect: Equatable, Sendable {
    case captureScreens
    case showOverlays
    case dismissOverlays
    case render
    case showPermissionGuidance
    case notifyCaptureFailure
    case saveScreenshot
    case copyScreenshot
    case playExpirySound
    case startLiveStream
    case stopLiveStream
    case freezeLiveFrame
    case startRecording
    case stopRecording
    case showRecordingNotice
    case dismissRecordingNotice
}

public enum RecordingPhase: Equatable, Sendable {
    /// Not recording.
    case off
    /// The "recording is starting" notice is showing; capture hasn't begun.
    case pending
    /// Capture is running.
    case active
}

public struct SessionStateMachine: Sendable {
    public private(set) var state: SessionState = .idle
    public private(set) var settings: Settings
    public private(set) var recordingPhase: RecordingPhase = .off

    /// True only while capture is actually running (not during the notice).
    public var isRecording: Bool { recordingPhase == .active }

    public init(settings: Settings) {
        self.settings = settings.sanitized()
    }

    @discardableResult
    public mutating func handle(_ event: SessionEvent) -> [SessionEffect] {
        switch event {
        case .settingsChanged(let s):
            settings = s.sanitized()
            return []
        case .hotkey(.toggleRecord, _, _):
            switch recordingPhase {
            case .off:
                recordingPhase = .pending
                return [.showRecordingNotice]
            case .pending:
                recordingPhase = .off
                return [.dismissRecordingNotice]
            case .active:
                recordingPhase = .off
                return [.stopRecording]
            }
        case .recordingNoticeElapsed:
            guard recordingPhase == .pending else { return [] }
            recordingPhase = .active
            return [.dismissRecordingNotice, .startRecording]
        case .recordingFailed:
            guard recordingPhase == .active else { return [] }
            recordingPhase = .off
            return [.notifyCaptureFailure]
        case .displayConfigurationChanged:
            var effects: [SessionEffect] = []
            switch recordingPhase {
            case .pending:
                recordingPhase = .off
                effects.append(.dismissRecordingNotice)
            case .active:
                recordingPhase = .off
                effects.append(.stopRecording)
            case .off:
                break
            }
            if case .idle = state { return effects }
            let wasLive = if case .liveZoom = state { true } else { false }
            state = .idle
            effects.append(contentsOf: wasLive ? [.stopLiveStream, .dismissOverlays] : [.dismissOverlays])
            return effects
        default:
            break
        }
        switch state {
        case .idle:
            return handleIdle(event)
        case .capturing(let target):
            return handleCapturing(event, target: target)
        case .zoom(let ctx):
            return handleZoom(event, ctx)
        case .liveZoom(let ctx):
            return handleLiveZoom(event, ctx)
        case .draw(let ctx):
            return handleDraw(event, ctx)
        case .type(let ctx, let tool):
            return handleType(event, ctx, tool)
        case .breakTimer(let ctx):
            return handleBreak(event, ctx)
        }
    }

    private func newCanvas() -> AnnotationCanvas {
        AnnotationCanvas(color: settings.penColor, penWidth: settings.penWidth)
    }

    private mutating func handleIdle(_ event: SessionEvent) -> [SessionEffect] {
        switch event {
        case .hotkey(.toggleZoom, let mouse, let screen):
            state = .capturing(.zoom(mouse: mouse, screen: screen))
            return [.captureScreens]
        case .hotkey(.toggleDraw, _, _):
            state = .draw(DrawContext(canvas: newCanvas(), zoom: nil))
            return [.showOverlays, .render]
        case .hotkey(.toggleLiveZoom, let mouse, let screen):
            state = .liveZoom(ZoomContext(level: settings.defaultZoomLevel, mouse: mouse, screen: screen))
            return [.showOverlays, .startLiveStream, .render]
        case .breakRequested(let now):
            if case .fadedDesktop = settings.breakTimer.background {
                state = .capturing(.breakTimer(now: now))
                return [.captureScreens]
            }
            return enterBreak(now: now, usedFallback: false)
        default:
            return []
        }
    }

    private mutating func enterBreak(now: TimeInterval, usedFallback: Bool) -> [SessionEffect] {
        let timer = BreakTimer(duration: settings.breakTimer.duration, startedAt: now)
        state = .breakTimer(BreakContext(timer: timer, usedFallbackBackground: usedFallback))
        return [.showOverlays, .render]
    }

    private mutating func handleCapturing(_ event: SessionEvent, target: CaptureTarget) -> [SessionEffect] {
        switch (event, target) {
        case (.captureCompleted, .zoom(let mouse, let screen)):
            state = .zoom(ZoomContext(level: settings.defaultZoomLevel, mouse: mouse, screen: screen))
            return [.showOverlays, .render]
        case (.captureCompleted, .breakTimer(let now)):
            return enterBreak(now: now, usedFallback: false)
        case (.captureFailed(.permissionDenied), .zoom):
            state = .idle
            return [.showPermissionGuidance]
        case (.captureFailed(.captureError), .zoom):
            state = .idle
            return [.notifyCaptureFailure]
        case (.captureFailed, .breakTimer(let now)):
            return enterBreak(now: now, usedFallback: true)
        case (.escape, _):
            state = .idle
            return []
        default:
            return []
        }
    }

    private mutating func handleBreak(_ event: SessionEvent, _ ctx: BreakContext) -> [SessionEffect] {
        var ctx = ctx
        switch event {
        case .escape, .rightMouseAction, .breakRequested, .hotkey:
            state = .idle
            return [.dismissOverlays]
        case .breakTick(let now):
            guard ctx.timer.isExpired(at: now), !ctx.soundPlayed else {
                state = .breakTimer(ctx)
                return [.render]
            }
            ctx.soundPlayed = true
            var effects: [SessionEffect] = []
            if settings.breakTimer.playSound { effects.append(.playExpirySound) }
            if settings.breakTimer.showElapsedAfterExpiry {
                state = .breakTimer(ctx)
                effects.append(.render)
            } else {
                state = .idle
                effects.append(.dismissOverlays)
            }
            return effects
        case .breakPauseResume(let now):
            guard !ctx.timer.isExpired(at: now) else { return [] }
            if ctx.timer.isPaused {
                ctx.timer.resume(at: now)
            } else {
                ctx.timer.pause(at: now)
            }
            state = .breakTimer(ctx)
            return [.render]
        case .breakAdjust(let seconds, let now):
            ctx.timer.adjust(by: seconds, at: now)
            if !ctx.timer.isExpired(at: now) { ctx.soundPlayed = false }
            state = .breakTimer(ctx)
            return [.render]
        default:
            return []
        }
    }

    private mutating func handleZoom(_ event: SessionEvent, _ ctx: ZoomContext) -> [SessionEffect] {
        var ctx = ctx
        switch event {
        case .escape, .rightMouseAction, .hotkey(.toggleZoom, _, _), .breakRequested:
            state = .idle
            return [.dismissOverlays]
        case .zoomChanged(let factor):
            ctx.level = ZoomGeometry.clamp(ctx.level * factor)
            state = .zoom(ctx)
            return [.render]
        case .mouseMoved(let point):
            ctx.mouse = point
            state = .zoom(ctx)
            return [.render]
        case .leftMouseDown, .hotkey(.toggleDraw, _, _):
            state = .draw(DrawContext(canvas: newCanvas(), zoom: ctx))
            return [.render]
        case .hotkey:
            state = .idle
            return [.dismissOverlays]
        default:
            return []
        }
    }

    private mutating func handleLiveZoom(_ event: SessionEvent, _ ctx: ZoomContext) -> [SessionEffect] {
        var ctx = ctx
        switch event {
        case .escape, .rightMouseAction, .breakRequested:
            state = .idle
            return [.stopLiveStream, .dismissOverlays]
        case .zoomChanged(let factor):
            ctx.level = ZoomGeometry.clamp(ctx.level * factor)
            state = .liveZoom(ctx)
            return [.render]
        case .mouseMoved(let point):
            ctx.mouse = point
            state = .liveZoom(ctx)
            return [.render]
        case .hotkey(.toggleDraw, _, _), .leftMouseDown:
            return [.freezeLiveFrame]
        case .liveFrameFrozen:
            state = .draw(DrawContext(canvas: newCanvas(), zoom: ctx, fromLiveZoom: true))
            return [.stopLiveStream, .render]
        case .hotkey:
            state = .idle
            return [.stopLiveStream, .dismissOverlays]
        case .liveStreamFailed(.permissionDenied):
            state = .idle
            return [.stopLiveStream, .dismissOverlays, .showPermissionGuidance]
        case .liveStreamFailed(.captureError):
            state = .idle
            return [.stopLiveStream, .dismissOverlays, .notifyCaptureFailure]
        default:
            return []
        }
    }

    private mutating func handleDraw(_ event: SessionEvent, _ ctx: DrawContext) -> [SessionEffect] {
        var ctx = ctx
        switch event {
        case .annotationAdded(let annotation):
            ctx.canvas.add(annotation)
        case .keyCommand(.color(let color)):
            ctx.canvas.color = color
        case .keyCommand(.undo), .rightMouseAction:
            ctx.canvas.undo()
        case .keyCommand(.eraseAll):
            ctx.canvas.eraseAll()
        case .keyCommand(.whiteboard):
            ctx.canvas.background = ctx.canvas.background == .white ? .transparent : .white
        case .keyCommand(.blackboard):
            ctx.canvas.background = ctx.canvas.background == .black ? .transparent : .black
        case .penWidthChanged(let delta):
            ctx.canvas.penWidth += delta
        case .keyCommand(.enterType):
            state = .type(ctx, TypeTool())
            return [.render]
        case .keyCommand(.save):
            return [.saveScreenshot]
        case .keyCommand(.copy):
            return [.copyScreenshot]
        case .escape, .hotkey(.toggleDraw, _, _):
            if let zoom = ctx.zoom {
                if ctx.fromLiveZoom {
                    state = .liveZoom(zoom)
                    return [.startLiveStream, .render]
                }
                state = .zoom(zoom)
                return [.render]
            }
            state = .idle
            return [.dismissOverlays]
        case .hotkey(.toggleZoom, _, _), .hotkey(.toggleLiveZoom, _, _), .breakRequested:
            state = .idle
            return [.dismissOverlays]
        default:
            return []
        }
        state = .draw(ctx)
        return [.render]
    }

    private mutating func handleType(_ event: SessionEvent, _ ctx: DrawContext, _ tool: TypeTool) -> [SessionEffect] {
        var ctx = ctx
        var tool = tool

        func commitRun() {
            if let annotation = tool.finish(color: ctx.canvas.color) {
                ctx.canvas.add(annotation)
            }
        }

        switch event {
        case .textInput(let s):
            tool.insert(s)
        case .deleteBackward:
            tool.deleteBackward()
        case .leftMouseDown(let point):
            commitRun()
            tool.beginText(at: point)
        case .keyCommand(.fontIncrease):
            tool.increaseFontSize()
        case .keyCommand(.fontDecrease):
            tool.decreaseFontSize()
        case .escape:
            commitRun()
            state = .draw(ctx)
            return [.render]
        case .hotkey, .breakRequested:
            commitRun()
            state = .idle
            return [.dismissOverlays]
        default:
            return []
        }
        state = .type(ctx, tool)
        return [.render]
    }
}
