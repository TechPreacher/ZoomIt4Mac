import Testing
import Foundation
import ZoomItCore

final class FakePersistence: SettingsPersisting {
    var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func set(_ data: Data, forKey key: String) { storage[key] = data }
}

struct SettingsStoreTests {
    @Test func loadWithNoDataReturnsDefaults() {
        let store = SettingsStore(persistence: FakePersistence())
        #expect(store.load() == .default)
    }

    @Test func saveThenLoadRoundTrips() {
        let store = SettingsStore(persistence: FakePersistence())
        var s = Settings.default
        s.penColor = .yellow
        s.defaultZoomLevel = 4
        store.save(s)
        #expect(store.load() == s)
    }

    @Test func corruptDataFallsBackToDefaults() {
        let p = FakePersistence()
        p.storage["zoomit.settings.v1"] = Data("not json".utf8)
        let store = SettingsStore(persistence: p)
        #expect(store.load() == .default)
    }

    @Test func outOfRangeValuesSanitizedOnLoad() throws {
        let p = FakePersistence()
        var s = Settings.default
        s.defaultZoomLevel = 99
        s.penWidth = 0
        p.storage["zoomit.settings.v1"] = try JSONEncoder().encode(s)
        let loaded = SettingsStore(persistence: p).load()
        #expect(loaded.defaultZoomLevel == 8)
        #expect(loaded.penWidth == 1)
    }
}

struct SettingsBreakMigrationTests {
    @Test func v1JSONWithoutBreakKeyDecodesToDefaults() throws {
        // Persisted by the v1 app: no breakTimer field existed.
        let store = SettingsStore(persistence: FakePersistence())
        var v1 = Settings.default
        v1.penColor = .green
        let encoder = JSONEncoder()
        var object = try JSONSerialization.jsonObject(with: encoder.encode(v1)) as! [String: Any]
        object.removeValue(forKey: "breakTimer")
        let v1Data = try JSONSerialization.data(withJSONObject: object)

        let p = FakePersistence()
        p.storage["zoomit.settings.v1"] = v1Data
        let loaded = SettingsStore(persistence: p).load()
        #expect(loaded.penColor == .green)               // old fields preserved
        #expect(loaded.breakTimer == .default)           // new field defaulted
        _ = store // silence unused warning
    }

    @Test func breakConfigSanitizedOnLoad() throws {
        let p = FakePersistence()
        var s = Settings.default
        s.breakTimer.duration = 1
        p.storage["zoomit.settings.v1"] = try JSONEncoder().encode(s)
        let loaded = SettingsStore(persistence: p).load()
        #expect(loaded.breakTimer.duration == 60)
    }
}

struct SettingsRecordingMigrationTests {
    @Test func jsonWithoutRecordingKeyDecodesToDefaults() throws {
        var s = Settings.default
        s.penColor = .blue
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        object.removeValue(forKey: "recording")
        let p = FakePersistence()
        p.storage["zoomit.settings.v1"] = try JSONSerialization.data(withJSONObject: object)
        let loaded = SettingsStore(persistence: p).load()
        #expect(loaded.penColor == .blue)
        #expect(loaded.recording == .default)
    }

    @Test func recordingRoundTripsThroughStore() {
        let store = SettingsStore(persistence: FakePersistence())
        var s = Settings.default
        s.recording.recordSystemAudio = true
        s.recording.recordMicrophone = false
        store.save(s)
        #expect(store.load().recording == s.recording)
    }
}
