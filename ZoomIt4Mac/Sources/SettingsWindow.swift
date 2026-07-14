import AppKit
import ServiceManagement
import SwiftUI
import ZoomItCore

func comboLabel(_ combo: KeyCombo) -> String {
    var s = ""
    if combo.modifiers.contains(.control) { s += "⌃" }
    if combo.modifiers.contains(.option) { s += "⌥" }
    if combo.modifiers.contains(.shift) { s += "⇧" }
    if combo.modifiers.contains(.command) { s += "⌘" }
    let keyNames: [UInt32: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
        40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
        32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z", 49: "Space", 36: "Return",
    ]
    return s + (keyNames[combo.keyCode] ?? "key\(combo.keyCode)")
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: ZoomItCore.Settings
    @Published var recordingAction: HotkeyAction?
    @Published var launchAtLogin: Bool

    private let store: SettingsStore
    private let onApply: (ZoomItCore.Settings) -> Void
    private var keyMonitor: Any?

    init(store: SettingsStore, onApply: @escaping (ZoomItCore.Settings) -> Void) {
        self.store = store
        self.onApply = onApply
        self.settings = store.load()
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var conflicts: Set<KeyCombo> { settings.hotkeys.conflictingCombos() }

    func beginRecording(_ action: HotkeyAction) {
        stopRecording()
        recordingAction = action
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.finishRecording(with: event)
            return nil // swallow the keystroke
        }
    }

    private func finishRecording(with event: NSEvent) {
        defer { stopRecording() }
        guard let action = recordingAction else { return }
        if event.keyCode == 53 { return } // Esc cancels recording
        var mods: KeyModifiers = []
        if event.modifierFlags.contains(.control) { mods.insert(.control) }
        if event.modifierFlags.contains(.option) { mods.insert(.option) }
        if event.modifierFlags.contains(.shift) { mods.insert(.shift) }
        if event.modifierFlags.contains(.command) { mods.insert(.command) }
        settings.hotkeys.set(KeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods), for: action)
        save()
    }

    private func stopRecording() {
        recordingAction = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func cancelRecording() {
        stopRecording()
    }

    func save() {
        store.save(settings)
        onApply(settings)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("launch-at-login change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Hotkeys") {
                hotkeyRow("Zoom", action: .toggleZoom)
                hotkeyRow("Draw", action: .toggleDraw)
                if !model.conflicts.isEmpty {
                    Text("Two actions share the same hotkey.")
                        .foregroundStyle(.red)
                }
            }
            Section("Zoom") {
                LabeledContent("Default zoom level") {
                    Slider(
                        value: Binding(
                            get: { model.settings.defaultZoomLevel },
                            set: { model.settings.defaultZoomLevel = $0; model.save() }
                        ),
                        in: 1...8, step: 0.5
                    )
                    Text(String(format: "%.1f×", model.settings.defaultZoomLevel))
                        .monospacedDigit()
                }
            }
            Section("Pen") {
                Picker("Default color", selection: Binding(
                    get: { model.settings.penColor },
                    set: { model.settings.penColor = $0; model.save() }
                )) {
                    ForEach(AnnotationColor.allCases, id: \.self) { color in
                        Text(color.rawValue.capitalized).tag(color)
                    }
                }
                LabeledContent("Width") {
                    Slider(
                        value: Binding(
                            get: { model.settings.penWidth },
                            set: { model.settings.penWidth = $0; model.save() }
                        ),
                        in: 1...20, step: 1
                    )
                    Text("\(Int(model.settings.penWidth)) pt").monospacedDigit()
                }
            }
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func hotkeyRow(_ title: String, action: HotkeyAction) -> some View {
        LabeledContent(title) {
            Button(
                model.recordingAction == action
                    ? "Press keys…"
                    : comboLabel(model.settings.hotkeys.combo(for: action))
            ) {
                model.beginRecording(action)
            }
            .foregroundStyle(
                model.conflicts.contains(model.settings.hotkeys.combo(for: action))
                    ? Color.red : Color.primary
            )
        }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var model: SettingsModel?
    private let store: SettingsStore
    private let onApply: (ZoomItCore.Settings) -> Void

    init(store: SettingsStore, onApply: @escaping (ZoomItCore.Settings) -> Void) {
        self.store = store
        self.onApply = onApply
    }

    func show() {
        if window == nil {
            let model = SettingsModel(store: store, onApply: onApply)
            self.model = model
            let view = SettingsView(model: model)
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "ZoomIt4Mac Settings"
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            window = w

            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: w, queue: .main
            ) { [weak model] _ in
                MainActor.assumeIsolated {
                    model?.cancelRecording()
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
