import AppKit
import ZoomItCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var hotkeyRegistrar: HotkeyRegistrar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(
            onZoom: { NSLog("zoom requested") },
            onDraw: { NSLog("draw requested") },
            onSettings: { NSLog("settings requested") }
        )
        let registrar = HotkeyRegistrar(onHotkey: { action in
            NSLog("hotkey fired: \(action.rawValue)")
        })
        let failed = registrar.apply(HotkeyConfiguration.default)
        if !failed.isEmpty {
            NSLog("hotkey registration failed for: \(failed.map(\.rawValue).joined(separator: ", "))")
        }
        hotkeyRegistrar = registrar
    }
}
