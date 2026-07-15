import CoreGraphics
import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var hotkeys: HotkeyConfiguration
    public var defaultZoomLevel: CGFloat
    public var penColor: AnnotationColor
    public var penWidth: CGFloat
    public var breakTimer: BreakConfiguration

    enum CodingKeys: String, CodingKey {
        case hotkeys
        case defaultZoomLevel
        case penColor
        case penWidth
        case breakTimer
    }

    public static let `default` = Settings(
        hotkeys: .default,
        defaultZoomLevel: 2.0,
        penColor: .red,
        penWidth: 4,
        breakTimer: .default
    )

    public init(
        hotkeys: HotkeyConfiguration,
        defaultZoomLevel: CGFloat,
        penColor: AnnotationColor,
        penWidth: CGFloat,
        breakTimer: BreakConfiguration
    ) {
        self.hotkeys = hotkeys
        self.defaultZoomLevel = defaultZoomLevel
        self.penColor = penColor
        self.penWidth = penWidth
        self.breakTimer = breakTimer
    }

    // Migration: v1 persisted JSON has no breakTimer key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeys = try container.decode(HotkeyConfiguration.self, forKey: .hotkeys)
        defaultZoomLevel = try container.decode(CGFloat.self, forKey: .defaultZoomLevel)
        penColor = try container.decode(AnnotationColor.self, forKey: .penColor)
        penWidth = try container.decode(CGFloat.self, forKey: .penWidth)
        breakTimer = try container.decodeIfPresent(BreakConfiguration.self, forKey: .breakTimer) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotkeys, forKey: .hotkeys)
        try container.encode(defaultZoomLevel, forKey: .defaultZoomLevel)
        try container.encode(penColor, forKey: .penColor)
        try container.encode(penWidth, forKey: .penWidth)
        try container.encode(breakTimer, forKey: .breakTimer)
    }

    public func sanitized() -> Settings {
        var s = self
        s.defaultZoomLevel = ZoomGeometry.clamp(defaultZoomLevel)
        s.penWidth = AnnotationCanvas.clampWidth(penWidth)
        s.breakTimer = breakTimer.sanitized()
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
