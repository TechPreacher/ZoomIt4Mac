import Testing
import CoreGraphics
import ZoomItCore

struct TypeToolTests {
    @Test func insertIgnoredBeforeCaretPlaced() {
        var t = TypeTool()
        t.insert("hello")
        #expect(t.text.isEmpty)
        #expect(t.finish(color: .red) == nil)
    }

    @Test func typingAfterBeginProducesAnnotation() {
        var t = TypeTool(fontSize: 32)
        t.beginText(at: CGPoint(x: 10, y: 20))
        t.insert("hi")
        #expect(t.finish(color: .blue) == .text("hi", at: CGPoint(x: 10, y: 20), color: .blue, fontSize: 32))
    }

    @Test func deleteBackwardRemovesLastCharacter() {
        var t = TypeTool()
        t.beginText(at: .zero)
        t.insert("ab")
        t.deleteBackward()
        #expect(t.text == "a")
        t.deleteBackward()
        t.deleteBackward() // extra delete on empty is a no-op
        #expect(t.text.isEmpty)
    }

    @Test func emptyOrWhitespaceRunDiscarded() {
        var t = TypeTool()
        t.beginText(at: .zero)
        t.insert("   ")
        #expect(t.finish(color: .red) == nil)
    }

    @Test func fontSizeClampsAtBounds() {
        var t = TypeTool(fontSize: 94)
        t.increaseFontSize()
        #expect(t.fontSize == 96)
        var s = TypeTool(fontSize: 13)
        s.decreaseFontSize()
        #expect(s.fontSize == 12)
        #expect(TypeTool(fontSize: 500).fontSize == 96)
        #expect(TypeTool(fontSize: 1).fontSize == 12)
    }

    @Test func beginTextAgainResetsRun() {
        var t = TypeTool()
        t.beginText(at: .zero)
        t.insert("first")
        t.beginText(at: CGPoint(x: 5, y: 5))
        #expect(t.text.isEmpty)
        #expect(t.origin == CGPoint(x: 5, y: 5))
    }
}
