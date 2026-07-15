import Testing
import Foundation
import ZoomItCore

struct BreakConfigurationTests {
    @Test func defaults() {
        let c = BreakConfiguration.default
        #expect(c.duration == 600)
        #expect(c.position == .center)
        #expect(c.opacity == 1.0)
        #expect(c.background == .solidBlack)
        #expect(c.showElapsedAfterExpiry)
        #expect(c.playSound)
    }

    @Test func sanitizeClampsDurationAndOpacity() {
        var c = BreakConfiguration.default
        c.duration = 5
        c.opacity = 7
        let s = c.sanitized()
        #expect(s.duration == 60)
        #expect(s.opacity == 1.0)
        c.duration = 999_999
        c.opacity = 0
        let s2 = c.sanitized()
        #expect(s2.duration == 5940)
        #expect(s2.opacity == 0.1)
    }

    @Test func codableRoundTripAllBackgrounds() throws {
        for background in [BreakBackground.solidBlack, .fadedDesktop, .imageFile("/tmp/pic.png")] {
            var c = BreakConfiguration.default
            c.background = background
            c.position = .bottomRight
            let data = try JSONEncoder().encode(c)
            let back = try JSONDecoder().decode(BreakConfiguration.self, from: data)
            #expect(back == c)
        }
    }

    @Test func positionHasNineCases() {
        #expect(BreakPosition.allCases.count == 9)
    }
}
