import CoreGraphics
import Testing
import ZoomItCore

struct SnipGeometryTests {
    // MARK: normalized

    @Test func normalizesAllFourDragDirections() {
        let expected = CGRect(x: 10, y: 20, width: 30, height: 40)
        let a = CGPoint(x: 10, y: 20), b = CGPoint(x: 40, y: 60)
        #expect(SnipGeometry.normalized(anchor: a, current: b) == expected)
        #expect(SnipGeometry.normalized(anchor: b, current: a) == expected)
        #expect(SnipGeometry.normalized(anchor: CGPoint(x: 40, y: 20), current: CGPoint(x: 10, y: 60)) == expected)
        #expect(SnipGeometry.normalized(anchor: CGPoint(x: 10, y: 60), current: CGPoint(x: 40, y: 20)) == expected)
    }

    @Test func zeroDragNormalizesToEmptyRect() {
        let p = CGPoint(x: 5, y: 5)
        let r = SnipGeometry.normalized(anchor: p, current: p)
        #expect(r == CGRect(x: 5, y: 5, width: 0, height: 0))
    }

    // MARK: isValidSelection

    @Test func minimumSizeEnforced() {
        #expect(SnipGeometry.isValidSelection(CGRect(x: 0, y: 0, width: 4, height: 4)))
        #expect(!SnipGeometry.isValidSelection(CGRect(x: 0, y: 0, width: 3.9, height: 100)))
        #expect(!SnipGeometry.isValidSelection(CGRect(x: 0, y: 0, width: 100, height: 3.9)))
        #expect(!SnipGeometry.isValidSelection(.zero))
    }

    @Test func nonFiniteSelectionRejected() {
        #expect(!SnipGeometry.isValidSelection(CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)))
        #expect(!SnipGeometry.isValidSelection(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)))
        #expect(!SnipGeometry.isValidSelection(CGRect(x: 0, y: CGFloat.nan, width: 10, height: CGFloat.nan)))
    }

    // MARK: pixelCrop

    @Test func fullSelectionInsideDisplayAt1x() {
        // Display 1000×500 at origin; selection 100 pt square at (200, 300).
        // Top-left pixel origin: y = displayMaxY(500) - selMaxY(400) = 100.
        let crop = SnipGeometry.pixelCrop(
            selection: CGRect(x: 200, y: 300, width: 100, height: 100),
            displayFrame: CGRect(x: 0, y: 0, width: 1000, height: 500),
            scale: 1
        )
        #expect(crop == CGRect(x: 200, y: 100, width: 100, height: 100))
    }

    @Test func retinaScaleMultipliesEverything() {
        let crop = SnipGeometry.pixelCrop(
            selection: CGRect(x: 200, y: 300, width: 100, height: 100),
            displayFrame: CGRect(x: 0, y: 0, width: 1000, height: 500),
            scale: 2
        )
        #expect(crop == CGRect(x: 400, y: 200, width: 200, height: 200))
    }

    @Test func negativeOriginDisplay() {
        // Secondary display left of and below the main one.
        let display = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let crop = SnipGeometry.pixelCrop(
            selection: CGRect(x: -1820, y: -100, width: 200, height: 100),
            displayFrame: display,
            scale: 1
        )
        // x: -1820 - (-1920) = 100; y: displayMaxY(880) - selMaxY(0) = 880.
        #expect(crop == CGRect(x: 100, y: 880, width: 200, height: 100))
    }

    @Test func selectionPartiallyOffDisplayIsClamped() {
        let crop = SnipGeometry.pixelCrop(
            selection: CGRect(x: -50, y: -50, width: 100, height: 100),
            displayFrame: CGRect(x: 0, y: 0, width: 1000, height: 500),
            scale: 1
        )
        // Clamped to (0,0,50,50); top-left y = 500 - 50 = 450.
        #expect(crop == CGRect(x: 0, y: 450, width: 50, height: 50))
    }

    @Test func selectionFullyOffDisplayReturnsNil() {
        #expect(SnipGeometry.pixelCrop(
            selection: CGRect(x: 2000, y: 0, width: 100, height: 100),
            displayFrame: CGRect(x: 0, y: 0, width: 1000, height: 500),
            scale: 1
        ) == nil)
    }

    @Test func degenerateInputsReturnNil() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let sel = CGRect(x: 10, y: 10, width: 100, height: 100)
        #expect(SnipGeometry.pixelCrop(selection: sel, displayFrame: display, scale: 0) == nil)
        #expect(SnipGeometry.pixelCrop(selection: sel, displayFrame: display, scale: .nan) == nil)
        #expect(SnipGeometry.pixelCrop(selection: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100), displayFrame: display, scale: 1) == nil)
        // Sub-pixel sliver after clamping.
        #expect(SnipGeometry.pixelCrop(selection: CGRect(x: -99.8, y: 0, width: 100, height: 100), displayFrame: display, scale: 1) == nil)
        // Non-finite display frame.
        #expect(SnipGeometry.pixelCrop(selection: sel, displayFrame: CGRect(x: CGFloat.nan, y: 0, width: 1000, height: 500), scale: 1) == nil)
        #expect(SnipGeometry.pixelCrop(selection: sel, displayFrame: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 500), scale: 1) == nil)
    }

    @Test func recordingMinimumEdgeIsStricter() {
        let small = CGRect(x: 0, y: 0, width: 31, height: 31)
        let ok = CGRect(x: 0, y: 0, width: 32, height: 32)
        #expect(SnipGeometry.isValidSelection(small)) // 4pt default still passes
        #expect(!SnipGeometry.isValidSelection(small, minimumEdge: SnipGeometry.minimumRecordingEdge))
        #expect(SnipGeometry.isValidSelection(ok, minimumEdge: SnipGeometry.minimumRecordingEdge))
    }
}
