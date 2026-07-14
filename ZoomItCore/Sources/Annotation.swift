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
}
