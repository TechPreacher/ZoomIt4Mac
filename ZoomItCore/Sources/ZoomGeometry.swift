import CoreGraphics

public enum ZoomGeometry {
    public static let minZoom: CGFloat = 1.0
    public static let maxZoom: CGFloat = 8.0

    public static func clamp(_ level: CGFloat) -> CGFloat {
        guard level.isFinite else { return minZoom }
        return min(max(level, minZoom), maxZoom)
    }

    /// Sub-rect of the frozen screen image visible at `level`, following the
    /// mouse proportionally so every screen edge is reachable (ZoomIt mapping).
    public static func visibleRect(mouse: CGPoint, screen: CGRect, level: CGFloat) -> CGRect {
        let level = clamp(level)
        let size = CGSize(width: screen.width / level, height: screen.height / level)
        let tx = screen.width > 0 ? (mouse.x - screen.minX) / screen.width : 0
        let ty = screen.height > 0 ? (mouse.y - screen.minY) / screen.height : 0
        let t = CGPoint(x: min(max(tx, 0), 1), y: min(max(ty, 0), 1))
        return CGRect(
            x: screen.minX + t.x * (screen.width - size.width),
            y: screen.minY + t.y * (screen.height - size.height),
            width: size.width,
            height: size.height
        )
    }
}
