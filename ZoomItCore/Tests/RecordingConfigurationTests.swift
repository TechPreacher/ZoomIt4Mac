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

    // 16" MacBook Pro Retina full screen: 3456×2234 @ 30 fps.
    // h264: 3456*2234*30 * 0.07 = 16_213_478.4 → 16_213_478
    // hevc: 3456*2234*30 * 0.04 =  9_264_844.8 →  9_264_845
    @Test func bitrateForRetinaFullScreen() {
        #expect(RecordingCodec.h264.averageBitRate(width: 3456, height: 2234, frameRate: 30) == 16_213_478)
        #expect(RecordingCodec.hevc.averageBitRate(width: 3456, height: 2234, frameRate: 30) == 9_264_845)
    }

    @Test func bitrateClampsToFloor() {
        // 100×100 @ 30 fps is far below the 1 Mbps floor for both codecs.
        #expect(RecordingCodec.h264.averageBitRate(width: 100, height: 100, frameRate: 30) == 1_000_000)
        #expect(RecordingCodec.hevc.averageBitRate(width: 100, height: 100, frameRate: 30) == 1_000_000)
    }

    @Test func bitrateFloorOnDegenerateInput() {
        #expect(RecordingCodec.hevc.averageBitRate(width: 0, height: 0, frameRate: 30) == 1_000_000)
        #expect(RecordingCodec.h264.averageBitRate(width: -100, height: 100, frameRate: 30) == 1_000_000)
    }
}
