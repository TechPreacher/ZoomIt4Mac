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
    case snip
    case ocrSnip
    case regionRecord
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

public enum SnipKind: Equatable, Sendable {
    case image, text, record
}

public struct SnipContext: Equatable, Sendable {
    /// What happens to the selected region on release: image → clipboard
    /// bitmap (⌃6), text → on-device OCR to clipboard string (⌃⌥6).
    public var kind: SnipKind
    /// Selection drag endpoints in global screen points (== image space at
    /// 1×). Nil until the user presses the mouse button.
    public var anchor: CGPoint?
    public var current: CGPoint?

    public init(kind: SnipKind = .image, anchor: CGPoint? = nil, current: CGPoint? = nil) {
        self.kind = kind
        self.anchor = anchor
        self.current = current
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
    case snip(SnipContext)
}

public enum KeyCommand: Equatable, Sendable {
    case color(AnnotationColor)
    case undo, eraseAll, whiteboard, blackboard, enterType
    case save, copy
    case fontIncrease, fontDecrease
    case toggleHighlighter, toggleBlur
}

public enum SessionEvent: Equatable, Sendable {
    case hotkey(HotkeyAction, mouse: CGPoint, screen: CGRect)
    case captureCompleted
    case captureFailed(CaptureFailure)
    case escape
    case leftMouseDown(CGPoint)
    case leftMouseUp(CGPoint, optionHeld: Bool)
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
    case exportSnip(selection: CGRect, alsoSave: Bool)
    case recognizeText(selection: CGRect)
    case playExpirySound
    case startLiveStream
    case stopLiveStream
    case freezeLiveFrame
    case startRecording(region: CGRect?)
    case stopRecording
    case showRecordingNotice
    case dismissRecordingNotice
}

public enum RecordingPhase: Equatable, Sendable {
    /// Not recording.
    case off
    /// The "recording is starting" notice is showing; capture hasn't begun.
    /// region: selected area in global screen points; nil = full display.
    case pending(region: CGRect?)
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
                recordingPhase = .pending(region: nil)
                return [.showRecordingNotice]
            case .pending:
                recordingPhase = .off
                return [.dismissRecordingNotice]
            case .active:
                recordingPhase = .off
                return [.stopRecording]
            }
        case .hotkey(.regionRecord, _, _) where recordingPhase != .off:
            if case .active = recordingPhase {
                recordingPhase = .off
                return [.stopRecording]
            }
            recordingPhase = .off
            return [.dismissRecordingNotice]
        case .recordingNoticeElapsed:
            guard case .pending(let region) = recordingPhase else { return [] }
            recordingPhase = .active
            return [.dismissRecordingNotice, .startRecording(region: region)]
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
        case .snip(let ctx):
            return handleSnip(event, ctx)
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
        case .hotkey(.snip, _, _):
            state = .capturing(.snip)
            return [.captureScreens]
        case .hotkey(.ocrSnip, _, _):
            state = .capturing(.ocrSnip)
            return [.captureScreens]
        case .hotkey(.regionRecord, _, _):
            state = .capturing(.regionRecord)
            return [.captureScreens]
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
        case (.captureCompleted, .snip):
            state = .snip(SnipContext())
            return [.showOverlays, .render]
        case (.captureFailed(.permissionDenied), .snip):
            state = .idle
            return [.showPermissionGuidance]
        case (.captureFailed(.captureError), .snip):
            state = .idle
            return [.notifyCaptureFailure]
        case (.captureCompleted, .ocrSnip):
            state = .snip(SnipContext(kind: .text))
            return [.showOverlays, .render]
        case (.captureFailed(.permissionDenied), .ocrSnip):
            state = .idle
            return [.showPermissionGuidance]
        case (.captureFailed(.captureError), .ocrSnip):
            state = .idle
            return [.notifyCaptureFailure]
        case (.captureCompleted, .regionRecord):
            state = .snip(SnipContext(kind: .record))
            return [.showOverlays, .render]
        case (.captureFailed(.permissionDenied), .regionRecord):
            state = .idle
            return [.showPermissionGuidance]
        case (.captureFailed(.captureError), .regionRecord):
            state = .idle
            return [.notifyCaptureFailure]
        case (.escape, _):
            state = .idle
            return []
        default:
            return []
        }
    }

    private mutating func handleSnip(_ event: SessionEvent, _ ctx: SnipContext) -> [SessionEffect] {
        var ctx = ctx
        switch event {
        case .leftMouseDown(let point):
            ctx.anchor = point
            ctx.current = point
            state = .snip(ctx)
            return [.render]
        case .mouseMoved(let point):
            guard ctx.anchor != nil else { return [] }
            ctx.current = point
            state = .snip(ctx)
            return [.render]
        case .leftMouseUp(let point, let optionHeld):
            guard let anchor = ctx.anchor else { return [] }
            let selection = SnipGeometry.normalized(anchor: anchor, current: point)
            let minimumEdge = ctx.kind == .record
                ? SnipGeometry.minimumRecordingEdge
                : SnipGeometry.minimumSelectionEdge
            guard SnipGeometry.isValidSelection(selection, minimumEdge: minimumEdge) else {
                // Stray click / sub-minimum drag: clear and let the user retry.
                state = .snip(SnipContext(kind: ctx.kind))
                return [.render]
            }
            state = .idle
            // Export first — dismissOverlays clears the snapshot store the
            // crop reads from.
            switch ctx.kind {
            case .image:
                return [.exportSnip(selection: selection, alsoSave: optionHeld), .dismissOverlays]
            case .text:
                // optionHeld deliberately ignored: no save-to-file variant for text.
                return [.recognizeText(selection: selection), .dismissOverlays]
            case .record:
                // No snapshot read — overlays go first so the notice never
                // sits under them. optionHeld deliberately ignored.
                recordingPhase = .pending(region: selection)
                return [.dismissOverlays, .showRecordingNotice]
            }
        case .escape, .rightMouseAction, .hotkey, .breakRequested:
            state = .idle
            return [.dismissOverlays]
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
            ctx.canvas.penStyle = .normal
        case .keyCommand(.undo), .rightMouseAction:
            ctx.canvas.undo()
        case .keyCommand(.eraseAll):
            ctx.canvas.eraseAll()
        case .keyCommand(.whiteboard):
            ctx.canvas.background = ctx.canvas.background == .white ? .transparent : .white
            if ctx.canvas.penStyle == .blur { ctx.canvas.penStyle = .normal }
        case .keyCommand(.blackboard):
            ctx.canvas.background = ctx.canvas.background == .black ? .transparent : .black
            if ctx.canvas.penStyle == .blur { ctx.canvas.penStyle = .normal }
        case .keyCommand(.toggleHighlighter):
            ctx.canvas.penStyle = ctx.canvas.penStyle == .highlighter ? .normal : .highlighter
        case .keyCommand(.toggleBlur):
            // Blur needs a frozen snapshot behind the ink — zoom-backed draw only.
            guard ctx.zoom != nil else { return [.notifyCaptureFailure] }
            ctx.canvas.penStyle = ctx.canvas.penStyle == .blur ? .normal : .blur
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
        case .hotkey(.toggleZoom, _, _), .hotkey(.toggleLiveZoom, _, _), .hotkey(.snip, _, _), .breakRequested:
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
