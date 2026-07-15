import Testing
import CoreGraphics
import ZoomItCore

struct AnnotationTests {
    @Test func colorHasSixCases() {
        #expect(AnnotationColor.allCases.count == 6)
    }

    @Test func arrowHeadSymmetricOnHorizontalShaft() {
        let (l, r) = Annotation.arrowHead(from: .zero, to: CGPoint(x: 100, y: 0), length: 20)
        // both barbs behind the tip
        #expect(l.x < 100 && r.x < 100)
        // symmetric about the shaft
        #expect(abs(l.y + r.y) < 0.0001)
        #expect(abs(l.x - r.x) < 0.0001)
        // barb length correct
        let d = hypot(l.x - 100, l.y - 0)
        #expect(abs(d - 20) < 0.0001)
    }

    @Test func arrowHeadDegenerateShaftCollapsesToTip() {
        let tip = CGPoint(x: 5, y: 5)
        let (l, r) = Annotation.arrowHead(from: tip, to: tip, length: 20)
        #expect(l == tip && r == tip)
    }
}

struct AnnotationStyleTests {
    @Test func highlightedWrapsAnyGeometricCase() {
        let base = Annotation.line(from: .zero, to: CGPoint(x: 5, y: 5), color: .yellow, width: 4)
        let wrapped = Annotation.highlighted(base)
        #expect(wrapped == .highlighted(base))
        #expect(wrapped != base)
    }

    @Test func blurRectEquality() {
        let r = CGRect(x: 1, y: 2, width: 30, height: 40)
        #expect(Annotation.blurRect(r) == .blurRect(r))
        #expect(Annotation.blurRect(r) != .blurRect(r.insetBy(dx: 1, dy: 1)))
    }

    @Test func scalingWidthMultipliesStrokeCases() {
        let points = [CGPoint.zero, CGPoint(x: 10, y: 0)]
        #expect(Annotation.stroke(points: points, color: .red, width: 4).scalingWidth(by: 3)
            == .stroke(points: points, color: .red, width: 12))
        #expect(Annotation.line(from: .zero, to: CGPoint(x: 1, y: 1), color: .blue, width: 2).scalingWidth(by: 3)
            == .line(from: .zero, to: CGPoint(x: 1, y: 1), color: .blue, width: 6))
        #expect(Annotation.arrow(from: .zero, to: CGPoint(x: 1, y: 1), color: .blue, width: 2).scalingWidth(by: 3)
            == .arrow(from: .zero, to: CGPoint(x: 1, y: 1), color: .blue, width: 6))
        let rect = CGRect(x: 0, y: 0, width: 5, height: 5)
        #expect(Annotation.rectangle(rect, color: .green, width: 1).scalingWidth(by: 3)
            == .rectangle(rect, color: .green, width: 3))
        #expect(Annotation.ellipse(in: rect, color: .green, width: 1).scalingWidth(by: 3)
            == .ellipse(in: rect, color: .green, width: 3))
    }

    @Test func scalingWidthLeavesTextAndBlurUntouched() {
        let text = Annotation.text("hi", at: .zero, color: .red, fontSize: 32)
        #expect(text.scalingWidth(by: 3) == text)
        let blur = Annotation.blurRect(CGRect(x: 0, y: 0, width: 5, height: 5))
        #expect(blur.scalingWidth(by: 3) == blur)
    }

    @Test func scalingWidthRecursesIntoHighlighted() {
        let base = Annotation.line(from: .zero, to: CGPoint(x: 1, y: 1), color: .pink, width: 2)
        #expect(Annotation.highlighted(base).scalingWidth(by: 3)
            == .highlighted(.line(from: .zero, to: CGPoint(x: 1, y: 1), color: .pink, width: 6)))
    }
}
