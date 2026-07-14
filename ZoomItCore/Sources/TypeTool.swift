import CoreGraphics
import Foundation

public struct TypeTool: Equatable, Sendable {
    public static let minFontSize: CGFloat = 12
    public static let maxFontSize: CGFloat = 96
    private static let fontStep: CGFloat = 4

    public private(set) var origin: CGPoint?
    public private(set) var text: String = ""
    public private(set) var fontSize: CGFloat

    public init(fontSize: CGFloat = 32) {
        self.fontSize = Self.clampFont(fontSize)
    }

    private static func clampFont(_ s: CGFloat) -> CGFloat {
        guard s.isFinite else { return 32 }
        return min(max(s, minFontSize), maxFontSize)
    }

    public mutating func beginText(at point: CGPoint) {
        origin = point
        text = ""
    }

    public mutating func insert(_ s: String) {
        guard origin != nil else { return }
        text += s
    }

    public mutating func deleteBackward() {
        guard !text.isEmpty else { return }
        text.removeLast()
    }

    public mutating func increaseFontSize() { fontSize = Self.clampFont(fontSize + Self.fontStep) }
    public mutating func decreaseFontSize() { fontSize = Self.clampFont(fontSize - Self.fontStep) }

    public func finish(color: AnnotationColor) -> Annotation? {
        guard let origin,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return .text(text, at: origin, color: color, fontSize: fontSize)
    }
}
