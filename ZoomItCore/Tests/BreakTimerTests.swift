import Testing
import Foundation
import ZoomItCore

struct BreakTimerTests {
    @Test func countsDownFromDuration() {
        let t = BreakTimer(duration: 600, startedAt: 1000)
        #expect(t.remaining(at: 1000) == 600)
        #expect(t.remaining(at: 1300) == 300)
        #expect(t.remaining(at: 1600) == 0)
        #expect(t.remaining(at: 2000) == 0) // floored at zero
    }

    @Test func initClampsDuration() {
        #expect(BreakTimer(duration: 5, startedAt: 0).remaining(at: 0) == 60)
        #expect(BreakTimer(duration: 100_000, startedAt: 0).remaining(at: 0) == 5940)
    }

    @Test func expiryAndElapsed() {
        let t = BreakTimer(duration: 60, startedAt: 0)
        #expect(!t.isExpired(at: 59))
        #expect(t.isExpired(at: 60))
        #expect(t.elapsedAfterExpiry(at: 59) == 0)
        #expect(t.elapsedAfterExpiry(at: 90) == 30)
    }

    @Test func pauseFreezesRemaining() {
        var t = BreakTimer(duration: 600, startedAt: 0)
        t.pause(at: 100)
        #expect(t.isPaused)
        #expect(t.remaining(at: 100) == 500)
        #expect(t.remaining(at: 9999) == 500) // frozen
        #expect(!t.isExpired(at: 9999))       // paused timer never expires
        t.resume(at: 200)
        #expect(!t.isPaused)
        #expect(t.remaining(at: 200) == 500)
        #expect(t.remaining(at: 300) == 400)
    }

    @Test func multiplePauseResumeCyclesAccumulate() {
        var t = BreakTimer(duration: 600, startedAt: 0)
        t.pause(at: 100)   // 500 left
        t.resume(at: 150)
        t.pause(at: 250)   // ran 100 more, 400 left
        t.resume(at: 1000)
        #expect(t.remaining(at: 1100) == 300)
    }

    @Test func pauseWhenPausedIsNoOp() {
        var t = BreakTimer(duration: 600, startedAt: 0)
        t.pause(at: 100)
        t.pause(at: 200)
        #expect(t.remaining(at: 300) == 500)
        var s = BreakTimer(duration: 600, startedAt: 0)
        s.resume(at: 100) // resume while running: no-op
        #expect(s.remaining(at: 200) == 400)
    }

    @Test func adjustAddsAndClamps() {
        var t = BreakTimer(duration: 600, startedAt: 0)
        t.adjust(by: 60, at: 100)
        #expect(t.remaining(at: 100) == 560)
        t.adjust(by: -100_000, at: 100)
        #expect(t.remaining(at: 100) == 60)   // clamped low
        t.adjust(by: 100_000, at: 100)
        #expect(t.remaining(at: 100) == 5940) // clamped high
    }

    @Test func adjustAfterExpiryRestartsCountdown() {
        var t = BreakTimer(duration: 60, startedAt: 0)
        #expect(t.isExpired(at: 120))
        t.adjust(by: 60, at: 120)
        #expect(!t.isExpired(at: 120))
        #expect(t.remaining(at: 120) == 60)
        #expect(t.elapsedAfterExpiry(at: 120) == 0)
    }

    @Test func adjustWhilePaused() {
        var t = BreakTimer(duration: 600, startedAt: 0)
        t.pause(at: 100)
        t.adjust(by: 60, at: 500)
        #expect(t.isPaused)
        #expect(t.remaining(at: 999) == 560)
    }

    @Test func formatEdgeCases() {
        #expect(BreakTimer.format(0) == "0:00")
        #expect(BreakTimer.format(59) == "0:59")
        #expect(BreakTimer.format(60) == "1:00")
        #expect(BreakTimer.format(600) == "10:00")
        #expect(BreakTimer.format(5940) == "99:00")
        #expect(BreakTimer.format(59.4) == "1:00") // ceiling: countdown shows 1:00 until it hits 0:59
    }
}
