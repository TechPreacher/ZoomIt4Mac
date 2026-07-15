import Foundation

public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)

    // Encode as a bare integer ("modifiers": 1), not {"rawValue": 1} —
    // OptionSet does not get single-value Codable synthesis.
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: KeyModifiers

    public init(keyCode: UInt32, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum HotkeyAction: String, Codable, CaseIterable, Hashable, Sendable {
    case toggleZoom, toggleDraw, toggleBreak
}

public struct HotkeyConfiguration: Equatable, Sendable {
    private var bindings: [HotkeyAction: KeyCombo]

    public static let `default` = HotkeyConfiguration(bindings: [
        .toggleZoom: KeyCombo(keyCode: 18, modifiers: .control), // ⌃1
        .toggleDraw: KeyCombo(keyCode: 19, modifiers: .control), // ⌃2
        .toggleBreak: KeyCombo(keyCode: 20, modifiers: .control), // ⌃3
    ])

    public init(bindings: [HotkeyAction: KeyCombo]) {
        self.bindings = bindings
    }

    public func combo(for action: HotkeyAction) -> KeyCombo {
        bindings[action] ?? Self.default.bindings[action]!
    }

    public mutating func set(_ combo: KeyCombo, for action: HotkeyAction) {
        bindings[action] = combo
    }

    public func conflictingCombos() -> Set<KeyCombo> {
        var seen = Set<KeyCombo>()
        var conflicts = Set<KeyCombo>()
        for action in HotkeyAction.allCases {
            let combo = self.combo(for: action)
            if !seen.insert(combo).inserted { conflicts.insert(combo) }
        }
        return conflicts
    }
}

extension HotkeyConfiguration: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dict = try container.decode([String: KeyCombo].self, forKey: .bindings)
        var bindings: [HotkeyAction: KeyCombo] = [:]
        for (key, value) in dict {
            if let action = HotkeyAction(rawValue: key) {
                bindings[action] = value
            }
        }
        self.bindings = bindings
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let dict: [String: KeyCombo] = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        try container.encode(dict, forKey: .bindings)
    }

    private enum CodingKeys: String, CodingKey {
        case bindings
    }
}
