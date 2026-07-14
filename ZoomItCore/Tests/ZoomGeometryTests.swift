import Testing
import CoreGraphics
import ZoomItCore

struct ZoomGeometryClampTests {
    @Test func clampsBelowMin() { #expect(ZoomGeometry.clamp(0.5) == 1.0) }
    @Test func clampsAboveMax() { #expect(ZoomGeometry.clamp(9.0) == 8.0) }
    @Test func passesThroughInRange() { #expect(ZoomGeometry.clamp(2.5) == 2.5) }
    @Test func clampsNaNToMin() { #expect(ZoomGeometry.clamp(.nan) == 1.0) }
}

struct ZoomGeometryVisibleRectTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func fullScreenAtOneX() {
        let r = ZoomGeometry.visibleRect(mouse: CGPoint(x: 500, y: 400), screen: screen, level: 1)
        #expect(r == screen)
    }

    @Test func halfSizeAtTwoX() {
        let r = ZoomGeometry.visibleRect(mouse: CGPoint(x: 500, y: 400), screen: screen, level: 2)
        #expect(r.size == CGSize(width: 500, height: 400))
        #expect(r.origin == CGPoint(x: 250, y: 200))
    }

    @Test func mouseAtOriginCornerPinsRect() {
        let r = ZoomGeometry.visibleRect(mouse: screen.origin, screen: screen, level: 4)
        #expect(r.origin == screen.origin)
    }

    @Test func mouseAtFarCornerPinsRect() {
        let r = ZoomGeometry.visibleRect(mouse: CGPoint(x: 1000, y: 800), screen: screen, level: 4)
        #expect(r.maxX == screen.maxX)
        #expect(r.maxY == screen.maxY)
    }

    @Test func nonZeroScreenOrigin() {
        // display arranged left of main: negative origin
        let s = CGRect(x: -1000, y: 100, width: 1000, height: 800)
        let r = ZoomGeometry.visibleRect(mouse: CGPoint(x: -1000, y: 100), screen: s, level: 2)
        #expect(r.origin == s.origin)
        let r2 = ZoomGeometry.visibleRect(mouse: CGPoint(x: 0, y: 900), screen: s, level: 2)
        #expect(r2.maxX == s.maxX)
        #expect(r2.maxY == s.maxY)
    }

    @Test func everyCornerReachableAtEveryLevel() {
        for level in [1.5, 2.0, 4.0, 8.0] as [CGFloat] {
            let tl = ZoomGeometry.visibleRect(mouse: screen.origin, screen: screen, level: level)
            #expect(tl.origin == screen.origin)
            let br = ZoomGeometry.visibleRect(mouse: CGPoint(x: screen.maxX, y: screen.maxY), screen: screen, level: level)
            #expect(abs(br.maxX - screen.maxX) < 0.001)
            #expect(abs(br.maxY - screen.maxY) < 0.001)
        }
    }
}
