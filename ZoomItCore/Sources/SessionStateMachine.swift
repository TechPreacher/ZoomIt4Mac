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

    public init(canvas: AnnotationCanvas, zoom: ZoomContext?) {
        self.canvas = canvas
        self.zoom = zoom
    }
}

public enum CaptureFailure: Equatable, Sendable {
    case permissionDenied, captureError
}

public enum SessionState: Equatable, Sendable {
    case idle
    case capturing(mouse: CGPoint, screen: CGRect)
    case zoom(ZoomContext)
    case draw(DrawContext)
    case type(DrawContext, TypeTool)
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
}

public struct SessionStateMachine: Sendable {
    public private(set) var state: SessionState = .idle
    public private(set) var settings: Settings

    public init(settings: Settings) {
        self.settings = settings.sanitized()
    }

    @discardableResult
    public mutating func handle(_ event: SessionEvent) -> [SessionEffect] {
        switch event {
        case .settingsChanged(let s):
            settings = s.sanitized()
            return []
        case .displayConfigurationChanged:
            if case .idle = state { return [] }
            state = .idle
            return [.dismissOverlays]
        default:
            break
        }
        switch state {
        case .idle:
            return handleIdle(event)
        case .capturing(let mouse, let screen):
            return handleCapturing(event, mouse: mouse, screen: screen)
        case .zoom(let ctx):
            return handleZoom(event, ctx)
        case .draw(let ctx):
            return handleDraw(event, ctx)
        case .type(let ctx, let tool):
            return handleType(event, ctx, tool)
        }
    }

    private func newCanvas() -> AnnotationCanvas {
        AnnotationCanvas(color: settings.penColor, penWidth: settings.penWidth)
    }

    private mutating func handleIdle(_ event: SessionEvent) -> [SessionEffect] {
        switch event {
        case .hotkey(.toggleZoom, let mouse, let screen):
            state = .capturing(mouse: mouse, screen: screen)
            return [.captureScreens]
        case .hotkey(.toggleDraw, _, _):
            state = .draw(DrawContext(canvas: newCanvas(), zoom: nil))
            return [.showOverlays, .render]
        default:
            return []
        }
    }

    private mutating func handleCapturing(_ event: SessionEvent, mouse: CGPoint, screen: CGRect) -> [SessionEffect] {
        switch event {
        case .captureCompleted:
            state = .zoom(ZoomContext(level: settings.defaultZoomLevel, mouse: mouse, screen: screen))
            return [.showOverlays, .render]
        case .captureFailed(.permissionDenied):
            state = .idle
            return [.showPermissionGuidance]
        case .captureFailed(.captureError):
            state = .idle
            return [.notifyCaptureFailure]
        case .escape:
            state = .idle
            return []
        default:
            return []
        }
    }

    private mutating func handleZoom(_ event: SessionEvent, _ ctx: ZoomContext) -> [SessionEffect] {
        switch event {
        case .escape, .rightMouseAction, .hotkey(.toggleZoom, _, _):
            state = .idle
            return [.dismissOverlays]
        default:
            return [] // zoom interactions: Task 11
        }
    }

    private mutating func handleDraw(_ event: SessionEvent, _ ctx: DrawContext) -> [SessionEffect] {
        return [] // Task 12
    }

    private mutating func handleType(_ event: SessionEvent, _ ctx: DrawContext, _ tool: TypeTool) -> [SessionEffect] {
        return [] // Task 12
    }
}
