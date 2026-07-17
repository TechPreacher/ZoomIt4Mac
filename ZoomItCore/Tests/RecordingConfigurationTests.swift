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

    @Test func defaultCodecIsHEVC() {
        #expect(RecordingConfiguration.default.codec == .hevc)
    }

    @Test func codecRoundTrip() throws {
        var c = RecordingConfiguration.default
        c.codec = .h264
        let back = try JSONDecoder().decode(RecordingConfiguration.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }

    // Migration: JSON persisted before the codec field existed must decode
    // with the HEVC default. Pinned — do not update this JSON literal.
    @Test func migratesLegacyJSONWithoutCodec() throws {
        let legacy = Data(#"{"recordMicrophone":false,"recordSystemAudio":true}"#.utf8)
        let c = try JSONDecoder().decode(RecordingConfiguration.self, from: legacy)
        #expect(!c.recordMicrophone)
        #expect(c.recordSystemAudio)
        #expect(c.codec == .hevc)
    }
}
