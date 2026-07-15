import CoreGraphics

public enum AnnotationColor: String, CaseIterable, Codable, Equatable, Sendable {
    case red, green, blue, orange, yellow, pink
}

public enum Annotation: Equatable, Sendable {
    case stroke(points: [CGPoint], color: AnnotationColor, width: CGFloat)
    case line(from: CGPoint, to: CGPoint, color: AnnotationColor, width: CGFloat)
    case arrow(from: CGPoint, to: CGPoint, color: AnnotationColor, width: CGFloat)
    case rectangle(CGRect, color: AnnotationColor, width: CGFloat)
    case ellipse(in: CGRect, color: AnnotationColor, width: CGFloat)
    case text(String, at: CGPoint, color: AnnotationColor, fontSize: CGFloat)
    /// The wrapped annotation drawn as a highlighter stroke (translucent,
    /// wider, multiply-blended). Produced for every geometric shape.
    indirect case highlighted(Annotation)
    /// Region of the frozen snapshot rendered Gaussian-blurred (image space).
    case blurRect(CGRect)

    /// Barb endpoints for an arrowhead at `to`, ±30° off the shaft direction.
    public static func arrowHead(from: CGPoint, to: CGPoint, length: CGFloat) -> (left: CGPoint, right: CGPoint) {
        let dx = to.x - from.x, dy = to.y - from.y
        let len = hypot(dx, dy)
        guard len > 0 else { return (to, to) }
        let angle = atan2(dy, dx)
        let spread: CGFloat = .pi / 6
        let left = CGPoint(
            x: to.x - length * cos(angle - spread),
            y: to.y - length * sin(angle - spread)
        )
        let right = CGPoint(
            x: to.x - length * cos(angle + spread),
            y: to.y - length * sin(angle + spread)
        )
        return (left, right)
    }

    /// A copy with the stroke width of geometric cases multiplied; text and
    /// blur regions carry no stroke width and pass through unchanged.
    public func scalingWidth(by factor: CGFloat) -> Annotation {
        switch self {
        case let .stroke(points, color, width):
            .stroke(points: points, color: color, width: width * factor)
        case let .line(from, to, color, width):
            .line(from: from, to: to, color: color, width: width * factor)
        case let .arrow(from, to, color, width):
            .arrow(from: from, to: to, color: color, width: width * factor)
        case let .rectangle(rect, color, width):
            .rectangle(rect, color: color, width: width * factor)
        case let .ellipse(rect, color, width):
            .ellipse(in: rect, color: color, width: width * factor)
        case .text, .blurRect:
            self
        case let .highlighted(base):
            .highlighted(base.scalingWidth(by: factor))
        }
    }
}
