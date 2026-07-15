import CoreGraphics
import Foundation

public enum BreakPosition: String, Codable, CaseIterable, Equatable, Sendable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight
}

public enum BreakBackground: Codable, Equatable, Sendable {
    case solidBlack
    case fadedDesktop
    case imageFile(String)
}

public struct BreakConfiguration: Codable, Equatable, Sendable {
    public var duration: TimeInterval
    public var position: BreakPosition
    public var opacity: CGFloat
    public var background: BreakBackground
    public var showElapsedAfterExpiry: Bool
    public var playSound: Bool

    public static let `default` = BreakConfiguration(
        duration: 600,
        position: .center,
        opacity: 1.0,
        background: .solidBlack,
        showElapsedAfterExpiry: true,
        playSound: true
    )

    public func sanitized() -> BreakConfiguration {
        var c = self
        c.duration = min(max(duration.isFinite ? duration : 600, BreakTimer.minTotal), BreakTimer.maxTotal)
        c.opacity = min(max(opacity.isFinite ? opacity : 1.0, 0.1), 1.0)
        return c
    }
}
