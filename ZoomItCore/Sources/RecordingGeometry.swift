import CoreGraphics

/// Pure geometry for region recording: global-selection → ScreenCaptureKit
/// sourceRect conversion, and even-pixel output sizing.
public enum RecordingGeometry {
    /// Selection (global bottom-left-origin points) → SCStreamConfiguration
    /// sourceRect (display-relative points, top-left origin), clamped to the
    /// display. Nil when any input is degenerate or the clamped rect is
    /// under a point on either edge.
    public static func sourceRect(selection: CGRect, displayFrame: CGRect) -> CGRect? {
        guard selection.origin.x.isFinite, selection.origin.y.isFinite,
              selection.width.isFinite, selection.height.isFinite,
              displayFrame.origin.x.isFinite, displayFrame.origin.y.isFinite,
              displayFrame.width.isFinite, displayFrame.height.isFinite
        else { return nil }
        let clamped = selection.intersection(displayFrame)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return CGRect(
            x: clamped.minX - displayFrame.minX,
            y: displayFrame.maxY - clamped.maxY,
            width: clamped.width,
            height: clamped.height
        )
    }

    /// Output size in pixels, rounded down to even values (hardware encoders
    /// require even dimensions), floored at 2×2.
    public static func outputPixelSize(sourceRect: CGRect, scale: CGFloat) -> CGSize {
        guard scale.isFinite, scale > 0,
              sourceRect.width.isFinite, sourceRect.height.isFinite
        else { return CGSize(width: 2, height: 2) }
        let width = max(2, Int(sourceRect.width * scale) & ~1)
        let height = max(2, Int(sourceRect.height * scale) & ~1)
        return CGSize(width: width, height: height)
    }
}
