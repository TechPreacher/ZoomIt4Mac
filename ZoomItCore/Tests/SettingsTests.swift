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
