import Testing
import CoreGraphics
import ZoomItCore

struct ShapeTrackerTests {
    @Test func freehandCollectsPoints() {
        var t = ShapeTracker(shape: .freehand, start: .zero, color: .red, width: 4)
        t.update(CGPoint(x: 1, y: 1)); t.update(CGPoint(x: 2, y: 2))
        guard case let .stroke(points, color, width)? = t.finish() else {
            Issue.record("expected stroke"); return
        }
        #expect(points == [.zero, CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)])
        #expect(color == .red && width == 4)
    }

    @Test func freehandClickWithoutDragIsNil() {
        let t = ShapeTracker(shape: .freehand, start: .zero, color: .red, width: 4)
        #expect(t.finish() == nil)
    }

    @Test func lineProducesLine() {
        var t = ShapeTracker(shape: .line, start: CGPoint(x: 1, y: 1), color: .blue, width: 2)
        t.update(CGPoint(x: 50, y: 60))
        #expect(t.finish() == .line(from: CGPoint(x: 1, y: 1), to: CGPoint(x: 50, y: 60), color: .blue, width: 2))
    }

    @Test func degenerateLineIsNil() {
        var t = ShapeTracker(shape: .line, start: CGPoint(x: 1, y: 1), color: .blue, width: 2)
        t.update(CGPoint(x: 1, y: 1))
        #expect(t.finish() == nil)
    }

    @Test func arrowProducesArrow() {
        var t = ShapeTracker(shape: .arrow, start: .zero, color: .yellow, width: 3)
        t.update(CGPoint(x: 10, y: 0))
        #expect(t.finish() == .arrow(from: .zero, to: CGPoint(x: 10, y: 0), color: .yellow, width: 3))
    }

    @Test func rectangleNormalizedWhenDraggedUpLeft() {
        var t = ShapeTracker(shape: .rectangle, start: CGPoint(x: 100, y: 100), color: .green, width: 4)
        t.update(CGPoint(x: 20, y: 40))
        guard case let .rectangle(rect, _, _)? = t.finish() else {
            Issue.record("expected rectangle"); return
        }
        #expect(rect == CGRect(x: 20, y: 40, width: 80, height: 60))
    }

    @Test func ellipseNormalized() {
        var t = ShapeTracker(shape: .ellipse, start: CGPoint(x: 10, y: 30), color: .pink, width: 4)
        t.update(CGPoint(x: 0, y: 0))
        guard case let .ellipse(rect, _, _)? = t.finish() else {
            Issue.record("expected ellipse"); return
        }
        #expect(rect == CGRect(x: 0, y: 0, width: 10, height: 30))
    }
}
