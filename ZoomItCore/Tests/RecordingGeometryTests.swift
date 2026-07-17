import CoreGraphics
import Foundation
import Testing
import ZoomItCore

struct RecordingGeometryTests {
    // Display 1000×600 at global origin (0,0); AppKit bottom-left origin.
    let display = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func convertsToTopLeftDisplayRelative() {
        // Selection 100pt from left, top edge 150pt below display top.
        let selection = CGRect(x: 100, y: 250, width: 300, height: 200)
        let rect = RecordingGeometry.sourceRect(selection: selection, displayFrame: display)
        #expect(rect == CGRect(x: 100, y: 150, width: 300, height: 200))
    }

    @Test func clampsToDisplay() {
        let selection = CGRect(x: -50, y: -50, width: 200, height: 200)
        let rect = RecordingGeometry.sourceRect(selection: selection, displayFrame: display)
        #expect(rect == CGRect(x: 0, y: 450, width: 150, height: 150))
    }

    @Test func negativeOriginDisplay() {
        let display2 = CGRect(x: -1000, y: -600, width: 1000, height: 600)
        let selection = CGRect(x: -900, y: -500, width: 100, height: 100)
        let rect = RecordingGeometry.sourceRect(selection: selection, displayFrame: display2)
        #expect(rect == CGRect(x: 100, y: 400, width: 100, height: 100))
    }

    @Test func offDisplaySelectionIsNil() {
        let selection = CGRect(x: 2000, y: 2000, width: 100, height: 100)
        #expect(RecordingGeometry.sourceRect(selection: selection, displayFrame: display) == nil)
    }

    @Test func nanInputsAreNil() {
        let selection = CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100)
        #expect(RecordingGeometry.sourceRect(selection: selection, displayFrame: display) == nil)
    }

    @Test func outputSizeRoundsDownToEven() {
        // 101.5pt × 2× = 203px → 202; 100pt × 2× = 200 stays.
        let size = RecordingGeometry.outputPixelSize(sourceRect: CGRect(x: 0, y: 0, width: 101.5, height: 100), scale: 2)
        #expect(size == CGSize(width: 202, height: 200))
    }

    @Test func outputSizeFloorsAtTwo() {
        let size = RecordingGeometry.outputPixelSize(sourceRect: CGRect(x: 0, y: 0, width: 0.4, height: 0.4), scale: 1)
        #expect(size == CGSize(width: 2, height: 2))
        let degenerate = RecordingGeometry.outputPixelSize(sourceRect: CGRect(x: 0, y: 0, width: 100, height: 100), scale: -1)
        #expect(degenerate == CGSize(width: 2, height: 2))
    }
}
