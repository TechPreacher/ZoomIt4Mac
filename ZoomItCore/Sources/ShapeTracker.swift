import CoreGraphics

public enum ShapeKind: Equatable, Sendable {
    case freehand, line, arrow, rectangle, ellipse
}

public struct ShapeTracker: Equatable, Sendable {
    public let shape: ShapeKind
    public let start: CGPoint
    public let color: AnnotationColor
    public let width: CGFloat
    public let style: PenStyle
    private var points: [CGPoint]
    private var current: CGPoint

    public init(shape: ShapeKind, start: CGPoint, color: AnnotationColor, width: CGFloat, style: PenStyle = .normal) {
        self.shape = shape
        self.start = start
        self.color = color
        self.width = width
        self.style = style
        self.points = [start]
        self.current = start
    }

    public mutating func update(_ point: CGPoint) {
        current = point
        if shape == .freehand { points.append(point) }
    }

    public func finish() -> Annotation? {
        if style == .blur {
            // Blur ignores the shape: always a normalized rectangle.
            guard current != start else { return nil }
            return .blurRect(normalizedRect)
        }
        guard let base = baseAnnotation() else { return nil }
        return style == .highlighter ? .highlighted(base) : base
    }

    public func preview() -> Annotation? { finish() }

    private func baseAnnotation() -> Annotation? {
        switch shape {
        case .freehand:
            guard points.count >= 2 else { return nil }
            return .stroke(points: points, color: color, width: width)
        case .line:
            guard current != start else { return nil }
            return .line(from: start, to: current, color: color, width: width)
        case .arrow:
            guard current != start else { return nil }
            return .arrow(from: start, to: current, color: color, width: width)
        case .rectangle:
            guard current != start else { return nil }
            return .rectangle(normalizedRect, color: color, width: width)
        case .ellipse:
            guard current != start else { return nil }
            return .ellipse(in: normalizedRect, color: color, width: width)
        }
    }

    private var normalizedRect: CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }
}
