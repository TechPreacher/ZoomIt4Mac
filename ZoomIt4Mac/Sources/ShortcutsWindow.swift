import AppKit
import SwiftUI
import ZoomItCore

private struct Shortcut: Identifiable {
    let id = UUID()
    let keys: String
    let action: String
}

private struct ShortcutSection: Identifiable {
    let id = UUID()
    let title: String
    let shortcuts: [Shortcut]
}

private func makeSections(hotkeys: HotkeyConfiguration) -> [ShortcutSection] {
    [
        ShortcutSection(title: "Global", shortcuts: [
            Shortcut(keys: comboLabel(hotkeys.combo(for: .toggleZoom)), action: "Zoom — freeze and magnify the screen"),
            Shortcut(keys: comboLabel(hotkeys.combo(for: .toggleLiveZoom)), action: "Live Zoom — magnify the live screen"),
            Shortcut(keys: comboLabel(hotkeys.combo(for: .toggleDraw)), action: "Draw — annotate on screen"),
            Shortcut(keys: comboLabel(hotkeys.combo(for: .toggleBreak)), action: "Break Timer — full-screen countdown"),
            Shortcut(keys: comboLabel(hotkeys.combo(for: .toggleRecord)), action: "Recording — start/stop recording the screen"),
            Shortcut(keys: comboLabel(hotkeys.combo(for: .regionRecord)), action: "Record Region — record a screen area"),
            Shortcut(keys: comboLabel(hotkeys.combo(for: .snip)), action: "Snip — copy a screen region"),
            Shortcut(keys: comboLabel(hotkeys.combo(for: .ocrSnip)), action: "OCR Snip — copy text in a region"),
        ]),
        ShortcutSection(title: "While zooming", shortcuts: [
            Shortcut(keys: "Scroll / Pinch / ↑ ↓", action: "Change zoom level (1×–8×)"),
            Shortcut(keys: "Move mouse", action: "Pan"),
            Shortcut(keys: "Left click", action: "Draw on the zoomed image"),
            Shortcut(keys: "Right click / Esc", action: "Exit zoom"),
        ]),
        ShortcutSection(title: "While live zooming", shortcuts: [
            Shortcut(keys: "Scroll / Pinch / ↑ ↓", action: "Change zoom level (1×–8×)"),
            Shortcut(keys: "Move mouse", action: "Pan"),
            Shortcut(keys: "Left click", action: "Freeze the frame and draw on it (Esc returns to live)"),
            Shortcut(keys: "Right click / Esc", action: "Exit live zoom"),
        ]),
        ShortcutSection(title: "While snipping", shortcuts: [
            Shortcut(keys: "Drag", action: "Select the region"),
            Shortcut(keys: "Release", action: "Copy the region (Snip), copy its text (OCR Snip), or start recording (Record Region)"),
            Shortcut(keys: "⌥ Release", action: "Copy and save as PNG (image snip only)"),
            Shortcut(keys: "Right click / Esc", action: "Cancel"),
        ]),
        ShortcutSection(title: "While drawing", shortcuts: [
            Shortcut(keys: "Drag", action: "Freehand pen"),
            Shortcut(keys: "⇧ Drag", action: "Straight line"),
            Shortcut(keys: "⌃⇧ Drag", action: "Arrow"),
            Shortcut(keys: "⌃ Drag", action: "Rectangle"),
            Shortcut(keys: "Hold ⇥ + Drag", action: "Ellipse"),
            Shortcut(keys: "R G B O Y P", action: "Pen color (red, green, blue, orange, yellow, pink)"),
            Shortcut(keys: "⌘ Scroll", action: "Pen width"),
            Shortcut(keys: "⌘Z / Right click", action: "Undo"),
            Shortcut(keys: "E", action: "Erase all"),
            Shortcut(keys: "W / K", action: "Whiteboard / blackboard"),
            Shortcut(keys: "H", action: "Highlighter pen (toggle)"),
            Shortcut(keys: "X", action: "Blur pen — drag a rectangle (frozen zoom only)"),
            Shortcut(keys: "T", action: "Type text"),
            Shortcut(keys: "⌘S / ⌘C", action: "Save as PNG / copy to clipboard"),
            Shortcut(keys: "Esc", action: "Back to zoom, or exit"),
        ]),
        ShortcutSection(title: "During a break", shortcuts: [
            Shortcut(keys: "Space", action: "Pause / resume"),
            Shortcut(keys: "↑ ↓ / Scroll", action: "Add / remove one minute"),
            Shortcut(keys: "Right click / Esc", action: "End the break"),
        ]),
        ShortcutSection(title: "While typing", shortcuts: [
            Shortcut(keys: "Click", action: "Place the caret"),
            Shortcut(keys: "⌘+ / ⌘−", action: "Font size"),
            Shortcut(keys: "⌫", action: "Delete backward"),
            Shortcut(keys: "Esc", action: "Done typing"),
        ]),
    ]
}

private struct ShortcutsView: View {
    let sections: [ShortcutSection]

    var body: some View {
        Form {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.shortcuts) { shortcut in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(shortcut.keys)
                                .monospaced()
                                .frame(width: 150, alignment: .leading)
                            Text(shortcut.action)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }
}

@MainActor
final class ShortcutsWindowController {
    private var window: NSWindow?
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        // Rebuild content on every show so rebound hotkeys are reflected.
        let view = ShortcutsView(sections: makeSections(hotkeys: store.load().hotkeys))
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Keyboard Shortcuts"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.contentView = NSHostingView(rootView: view)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
