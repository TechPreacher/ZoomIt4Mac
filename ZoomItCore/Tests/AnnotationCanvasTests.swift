import Testing
import CoreGraphics
import ZoomItCore

struct AnnotationCanvasTests {
    func makeLine(_ x: CGFloat) -> Annotation {
        .line(from: .zero, to: CGPoint(x: x, y: 0), color: .red, width: 4)
    }

    @Test func addAppendsInOrder() {
        var c = AnnotationCanvas()
        c.add(makeLine(1)); c.add(makeLine(2))
        #expect(c.annotations == [makeLine(1), makeLine(2)])
    }

    @Test func undoRemovesLast() {
        var c = AnnotationCanvas()
        c.add(makeLine(1)); c.add(makeLine(2))
        c.undo()
        #expect(c.annotations == [makeLine(1)])
    }

    @Test func undoOnEmptyIsNoOp() {
        var c = AnnotationCanvas()
        c.undo()
        #expect(c.annotations.isEmpty)
    }

    @Test func eraseAllThenUndoRestores() {
        var c = AnnotationCanvas()
        c.add(makeLine(1)); c.add(makeLine(2))
        c.eraseAll()
        #expect(c.annotations.isEmpty)
        c.undo()
        #expect(c.annotations == [makeLine(1), makeLine(2)])
    }

    @Test func unlimitedUndoWithinSession() {
        var c = AnnotationCanvas()
        for i in 1...100 { c.add(makeLine(CGFloat(i))) }
        for _ in 1...100 { c.undo() }
        #expect(c.annotations.isEmpty)
    }

    @Test func penWidthClamps() {
        var c = AnnotationCanvas()
        c.penWidth = 0
        #expect(c.penWidth == 1)
        c.penWidth = 99
        #expect(c.penWidth == 20)
    }

    @Test func backgroundDefaultsTransparentAndEraseKeepsIt() {
        var c = AnnotationCanvas()
        #expect(c.background == .transparent)
        c.background = .white
        c.eraseAll()
        #expect(c.background == .white)
    }
}
