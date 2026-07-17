import CoreGraphics

/// Pure geometry for the snip selection: rect normalization, the minimum
/// useful selection size, and the points→snapshot-pixel crop conversion.
public enum SnipGeometry {
    /// A release smaller than this (either edge, in points) is treated as a
    /// stray click, not a selection.
    public static let minimumSelectionEdge: CGFloat = 4

    /// Recording needs a substantially larger region than a snip — tiny
    /// regions produce degenerate encoder dimensions.
    public static let minimumRecordingEdge: CGFloat = 32

    /// Rectangle spanned by a drag, whatever its direction.
    public static func normalized(anchor: CGPoint, current: CGPoint) -> CGRect {
        CGRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: abs(current.x - anchor.x),
            height: abs(current.y - anchor.y)
        )
    }

    public static func isValidSelection(_ rect: CGRect, minimumEdge: CGFloat = SnipGeometry.minimumSelectionEdge) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width >= minimumEdge
            && rect.height >= minimumEdge
    }

    /// Selection (global bottom-left-origin points) → pixel rect in the
    /// display's snapshot (top-left origin), clamped to the display frame.
    /// Nil when the clamped selection is empty (or under a pixel) or any
    /// input is degenerate.
    public static func pixelCrop(selection: CGRect, displayFrame: CGRect, scale: CGFloat) -> CGRect? {
        guard scale.isFinite, scale > 0 else { return nil }
        guard selection.origin.x.isFinite, selection.origin.y.isFinite,
              selection.width.isFinite, selection.height.isFinite,
              displayFrame.origin.x.isFinite, displayFrame.origin.y.isFinite,
              displayFrame.width.isFinite, displayFrame.height.isFinite
        else { return nil }
        let clamped = selection.intersection(displayFrame)
        guard !clamped.isNull,
              clamped.width >= 1, clamped.height >= 1
        else { return nil }
        return CGRect(
            x: (clamped.minX - displayFrame.minX) * scale,
            y: (displayFrame.maxY - clamped.maxY) * scale,
            width: clamped.width * scale,
            height: clamped.height * scale
        )
    }
}
