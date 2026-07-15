import CoreGraphics

public enum CanvasBackground: Equatable, Sendable {
    case transparent, white, black
}

public enum PenStyle: Equatable, Sendable {
    case normal, highlighter, blur
}

public struct AnnotationCanvas: Equatable, Sendable {
    public private(set) var annotations: [Annotation] = []
    public var color: AnnotationColor
    public var background: CanvasBackground = .transparent
    public var penStyle: PenStyle = .normal

    public var penWidth: CGFloat {
        didSet { penWidth = Self.clampWidth(penWidth) }
    }

    private var undoStack: [[Annotation]] = []

    public init(color: AnnotationColor = .red, penWidth: CGFloat = 4) {
        self.color = color
        self.penWidth = Self.clampWidth(penWidth)
    }

    public static func clampWidth(_ w: CGFloat) -> CGFloat {
        guard w.isFinite else { return 4 }
        return min(max(w, 1), 20)
    }

    public mutating func add(_ annotation: Annotation) {
        undoStack.append(annotations)
        annotations.append(annotation)
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        annotations = previous
    }

    public mutating func eraseAll() {
        guard !annotations.isEmpty else { return }
        undoStack.append(annotations)
        annotations = []
    }
}
