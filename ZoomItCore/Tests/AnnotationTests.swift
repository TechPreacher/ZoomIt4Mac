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
