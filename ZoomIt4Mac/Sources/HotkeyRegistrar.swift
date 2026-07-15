import AppKit
import Carbon.HIToolbox
import ZoomItCore

extension KeyCombo {
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }
}

@MainActor
final class HotkeyRegistrar: NSObject {
    private let onHotkey: (HotkeyAction) -> Void
    private var hotKeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private static let signature: OSType = 0x5A49_544D // 'ZITM'

    // Carbon hands back an integer id; map ids to actions.
    private static let actionIDs: [UInt32: HotkeyAction] = {
        var map: [UInt32: HotkeyAction] = [:]
        for (i, action) in HotkeyAction.allCases.enumerated() {
            map[UInt32(i + 1)] = action
        }
        return map
    }()

    private static func id(for action: HotkeyAction) -> UInt32 {
        actionIDs.first(where: { $0.value == action })!.key
    }

    init(onHotkey: @escaping (HotkeyAction) -> Void) {
        self.onHotkey = onHotkey
        super.init()
        installHandler()
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                let registrar = Unmanaged<HotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    registrar.dispatch(id: hotKeyID.id)
                }
                return noErr
            },
            1, &eventType, selfPtr, &eventHandlerRef
        )
    }

    private func dispatch(id: UInt32) {
        guard let action = Self.actionIDs[id] else { return }
        onHotkey(action)
    }

    /// Registers all bindings; returns the set of actions whose combo could
    /// not be registered (already taken system-wide).
    @discardableResult
    func apply(_ config: HotkeyConfiguration) -> Set<HotkeyAction> {
        unregisterAll()
        var failed: Set<HotkeyAction> = []
        for action in HotkeyAction.allCases {
            let combo = config.combo(for: action)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                combo.keyCode,
                combo.carbonModifiers,
                EventHotKeyID(signature: Self.signature, id: Self.id(for: action)),
                GetEventDispatcherTarget(), 0, &ref
            )
            if status == noErr, let ref {
                hotKeyRefs[action] = ref
            } else {
                failed.insert(action)
            }
        }
        return failed
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
    }
}
