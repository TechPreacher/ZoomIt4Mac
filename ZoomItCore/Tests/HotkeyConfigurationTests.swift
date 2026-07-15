import Testing
import Foundation
import ZoomItCore

struct HotkeyConfigurationTests {
    @Test func defaultsAreCtrl1AndCtrl2() {
        let c = HotkeyConfiguration.default
        #expect(c.combo(for: .toggleZoom) == KeyCombo(keyCode: 18, modifiers: .control))
        #expect(c.combo(for: .toggleDraw) == KeyCombo(keyCode: 19, modifiers: .control))
    }

    @Test func noConflictsInDefaults() {
        #expect(HotkeyConfiguration.default.conflictingCombos().isEmpty)
    }

    @Test func duplicateComboDetected() {
        var c = HotkeyConfiguration.default
        let combo = KeyCombo(keyCode: 18, modifiers: .control)
        c.set(combo, for: .toggleDraw)
        #expect(c.conflictingCombos() == [combo])
    }

    @Test func setOverridesBinding() {
        var c = HotkeyConfiguration.default
        let combo = KeyCombo(keyCode: 11, modifiers: [.option, .command])
        c.set(combo, for: .toggleZoom)
        #expect(c.combo(for: .toggleZoom) == combo)
    }

    @Test func codableRoundTrip() throws {
        var c = HotkeyConfiguration.default
        c.set(KeyCombo(keyCode: 40, modifiers: [.control, .shift]), for: .toggleDraw)
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(HotkeyConfiguration.self, from: data)
        #expect(back == c)
    }

    @Test func missingBindingFallsBackToDefault() throws {
        // decode a config that only carries one binding
        let json = #"{"bindings":{"toggleZoom":{"keyCode":50,"modifiers":1}}}"#
        let c = try JSONDecoder().decode(HotkeyConfiguration.self, from: Data(json.utf8))
        #expect(c.combo(for: .toggleZoom) == KeyCombo(keyCode: 50, modifiers: .control))
        #expect(c.combo(for: .toggleDraw) == HotkeyConfiguration.default.combo(for: .toggleDraw))
    }

    @Test func snipDefaultIsCtrl6() {
        #expect(HotkeyConfiguration.default.combo(for: .snip) == KeyCombo(keyCode: 22, modifiers: .control))
    }

    @Test func settingsPersistedBeforeSnipFallBackToCtrl6() throws {
        // A config saved by the pre-snip app carries no "snip" key.
        let json = #"{"bindings":{"toggleZoom":{"keyCode":18,"modifiers":1},"toggleDraw":{"keyCode":19,"modifiers":1},"toggleBreak":{"keyCode":20,"modifiers":1},"toggleLiveZoom":{"keyCode":21,"modifiers":1},"toggleRecord":{"keyCode":23,"modifiers":1}}}"#
        let c = try JSONDecoder().decode(HotkeyConfiguration.self, from: Data(json.utf8))
        #expect(c.combo(for: .snip) == KeyCombo(keyCode: 22, modifiers: .control))
        #expect(c.combo(for: .toggleZoom) == KeyCombo(keyCode: 18, modifiers: .control))
    }
}
