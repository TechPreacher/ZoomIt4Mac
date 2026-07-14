import CoreGraphics
import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var hotkeys: HotkeyConfiguration
    public var defaultZoomLevel: CGFloat
    public var penColor: AnnotationColor
    public var penWidth: CGFloat

    public static let `default` = Settings(
        hotkeys: .default,
        defaultZoomLevel: 2.0,
        penColor: .red,
        penWidth: 4
    )

    public func sanitized() -> Settings {
        var s = self
        s.defaultZoomLevel = ZoomGeometry.clamp(defaultZoomLevel)
        s.penWidth = AnnotationCanvas.clampWidth(penWidth)
        return s
    }
}

public protocol SettingsPersisting: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
}

extension UserDefaults: SettingsPersisting {
    public func set(_ data: Data, forKey key: String) {
        set(data as Any, forKey: key)
    }
}

public final class SettingsStore {
    private static let key = "zoomit.settings.v1"
    private let persistence: SettingsPersisting

    public init(persistence: SettingsPersisting) {
        self.persistence = persistence
    }

    public func load() -> Settings {
        guard let data = persistence.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return .default }
        return settings.sanitized()
    }

    public func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings.sanitized()) else { return }
        persistence.set(data, forKey: Self.key)
    }
}
