import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
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

enum BackgroundKind: Hashable { case solid, desktop, image }

func backgroundKind(_ background: BreakBackground) -> BackgroundKind {
    switch background {
    case .solidBlack: .solid
    case .fadedDesktop: .desktop
    case .imageFile: .image
    }
}

func positionLabel(_ position: BreakPosition) -> String {
    switch position {
    case .topLeft: "Top left"
    case .top: "Top"
    case .topRight: "Top right"
    case .left: "Left"
    case .center: "Center"
    case .right: "Right"
    case .bottomLeft: "Bottom left"
    case .bottom: "Bottom"
    case .bottomRight: "Bottom right"
    }
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

    func setBreakBackgroundKind(_ kind: BackgroundKind) {
        switch kind {
        case .solid: settings.breakTimer.background = .solidBlack
        case .desktop: settings.breakTimer.background = .fadedDesktop
        case .image: chooseBreakImage()
        }
        save()
    }

    func chooseBreakImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            settings.breakTimer.background = .imageFile(url.path)
            save()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Hotkeys") {
                hotkeyRow("Zoom", action: .toggleZoom)
                hotkeyRow("Live Zoom", action: .toggleLiveZoom)
                hotkeyRow("Draw", action: .toggleDraw)
                hotkeyRow("Break Timer", action: .toggleBreak)
                hotkeyRow("Recording", action: .toggleRecord)
                hotkeyRow("Snip", action: .snip)
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
                        .fixedSize()
                        .frame(width: 44, alignment: .trailing)
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
                    Text("\(Int(model.settings.penWidth)) pt")
                        .monospacedDigit()
                        .fixedSize()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Section("Break Timer") {
                LabeledContent("Duration") {
                    Stepper(
                        value: Binding(
                            get: { model.settings.breakTimer.duration / 60 },
                            set: { model.settings.breakTimer.duration = $0 * 60; model.save() }
                        ),
                        in: 1...99
                    ) {
                        Text("\(Int(model.settings.breakTimer.duration / 60)) min")
                            .monospacedDigit()
                            .fixedSize()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                Picker("Position", selection: Binding(
                    get: { model.settings.breakTimer.position },
                    set: { model.settings.breakTimer.position = $0; model.save() }
                )) {
                    ForEach(BreakPosition.allCases, id: \.self) { position in
                        Text(positionLabel(position)).tag(position)
                    }
                }
                LabeledContent("Opacity") {
                    Slider(
                        value: Binding(
                            get: { model.settings.breakTimer.opacity },
                            set: { model.settings.breakTimer.opacity = $0; model.save() }
                        ),
                        in: 0.1...1.0
                    )
                    Text("\(Int(model.settings.breakTimer.opacity * 100)) %")
                        .monospacedDigit()
                        .fixedSize()
                        .frame(width: 44, alignment: .trailing)
                }
                Picker("Background", selection: Binding(
                    get: { backgroundKind(model.settings.breakTimer.background) },
                    set: { model.setBreakBackgroundKind($0) }
                )) {
                    Text("Solid black").tag(BackgroundKind.solid)
                    Text("Faded desktop").tag(BackgroundKind.desktop)
                    Text("Image…").tag(BackgroundKind.image)
                }
                if case .imageFile(let path) = model.settings.breakTimer.background {
                    LabeledContent("Image") {
                        Text((path as NSString).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { model.chooseBreakImage() }
                    }
                }
                Toggle("Show elapsed time after expiry", isOn: Binding(
                    get: { model.settings.breakTimer.showElapsedAfterExpiry },
                    set: { model.settings.breakTimer.showElapsedAfterExpiry = $0; model.save() }
                ))
                Toggle("Play sound on expiry", isOn: Binding(
                    get: { model.settings.breakTimer.playSound },
                    set: { model.settings.breakTimer.playSound = $0; model.save() }
                ))
            }
            Section("Recording") {
                Toggle("Record microphone", isOn: Binding(
                    get: { model.settings.recording.recordMicrophone },
                    set: { model.settings.recording.recordMicrophone = $0; model.save() }
                ))
                Text("macOS asks for microphone access the first time a recording starts with this enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Record system audio", isOn: Binding(
                    get: { model.settings.recording.recordSystemAudio },
                    set: { model.settings.recording.recordSystemAudio = $0; model.save() }
                ))
                Picker("Video codec", selection: Binding(
                    get: { model.settings.recording.codec },
                    set: { model.settings.recording.codec = $0; model.save() }
                )) {
                    Text("HEVC (smaller files)").tag(RecordingCodec.hevc)
                    Text("H.264 (most compatible)").tag(RecordingCodec.h264)
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
        // Grouped Form scrolls its content; let the window control the height
        // so the settings fit on small screens and stay vertically resizable.
        .frame(width: 420)
        .frame(minHeight: 300, maxHeight: .infinity)
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
            // Open as tall as the screen comfortably allows (capped at 720pt);
            // the grouped Form scrolls when content exceeds the window height.
            let available = (NSScreen.main?.visibleFrame.height ?? 800) - 80
            let height = min(720, available)
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: height),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "ZoomIt4Mac Settings"
            w.contentMinSize = NSSize(width: 420, height: 300)
            w.contentMaxSize = NSSize(width: 420, height: CGFloat.greatestFiniteMagnitude)
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
