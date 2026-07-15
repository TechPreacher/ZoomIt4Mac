import Foundation

/// Pure countdown model. All time is injected as monotonic timestamps so the
/// model is deterministic and testable; the shell supplies CACurrentMediaTime().
public struct BreakTimer: Equatable, Sendable {
    public static let minTotal: TimeInterval = 60
    public static let maxTotal: TimeInterval = 5940

    /// Absolute end timestamp while running; meaningless while paused.
    private var endTime: TimeInterval
    /// Non-nil while paused: the frozen remaining time.
    private var pausedRemaining: TimeInterval?

    public var isPaused: Bool { pausedRemaining != nil }

    public init(duration: TimeInterval, startedAt now: TimeInterval) {
        let clamped = min(max(duration, Self.minTotal), Self.maxTotal)
        self.endTime = now + clamped
        self.pausedRemaining = nil
    }

    public func remaining(at now: TimeInterval) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        return max(0, endTime - now)
    }

    public func isExpired(at now: TimeInterval) -> Bool {
        !isPaused && remaining(at: now) == 0
    }

    public func elapsedAfterExpiry(at now: TimeInterval) -> TimeInterval {
        guard isExpired(at: now) else { return 0 }
        return now - endTime
    }

    public mutating func pause(at now: TimeInterval) {
        guard !isPaused else { return }
        pausedRemaining = remaining(at: now)
    }

    public mutating func resume(at now: TimeInterval) {
        guard let frozen = pausedRemaining else { return }
        endTime = now + frozen
        pausedRemaining = nil
    }

    public mutating func adjust(by seconds: TimeInterval, at now: TimeInterval) {
        let target = min(max(remaining(at: now) + seconds, Self.minTotal), Self.maxTotal)
        if isPaused {
            pausedRemaining = target
        } else {
            endTime = now + target
        }
    }

    /// Ceiling to whole seconds so a countdown reads 1:00 until it reaches 0:59.
    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
