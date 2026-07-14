import AppKit
import ZoomItCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: SessionCoordinator?
    private var statusItemController: StatusItemController?
    private var hotkeyRegistrar: HotkeyRegistrar?
    private let settingsStore = SettingsStore(persistence: UserDefaults.standard)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = settingsStore.load()
        let coordinator = SessionCoordinator(
            settings: settings,
            snapshotter: ScreenSnapshotter(),
            permissions: PermissionCoordinator()
        )
        self.coordinator = coordinator

        statusItemController = StatusItemController(
            onZoom: { coordinator.trigger(.toggleZoom) },
            onDraw: { coordinator.trigger(.toggleDraw) },
            onSettings: { NSLog("settings requested") } // Task 19 replaces
        )

        let registrar = HotkeyRegistrar(onHotkey: { action in
            coordinator.trigger(action)
        })
        let failed = registrar.apply(settings.hotkeys)
        if !failed.isEmpty {
            NSLog("hotkey registration failed for: \(failed.map(\.rawValue).joined(separator: ", "))")
        }
        hotkeyRegistrar = registrar

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                coordinator.send(.displayConfigurationChanged)
            }
        }
    }
}
