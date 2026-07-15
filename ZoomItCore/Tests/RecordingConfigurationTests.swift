import Testing
import Foundation
import ZoomItCore

struct RecordingConfigurationTests {
    @Test func defaults() {
        let c = RecordingConfiguration.default
        #expect(c.recordMicrophone)
        #expect(!c.recordSystemAudio)
    }

    @Test func codableRoundTrip() throws {
        var c = RecordingConfiguration.default
        c.recordMicrophone = false
        c.recordSystemAudio = true
        let back = try JSONDecoder().decode(RecordingConfiguration.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }

    @Test func defaultRecordHotkeyIsCtrl5() {
        #expect(HotkeyConfiguration.default.combo(for: .toggleRecord) == KeyCombo(keyCode: 23, modifiers: .control))
        #expect(HotkeyConfiguration.default.conflictingCombos().isEmpty)
    }
}
