import AppKit
import Sparkle
import ZoomItCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: SessionCoordinator?
    private var statusItemController: StatusItemController?
    private var hotkeyRegistrar: HotkeyRegistrar?
    private var settingsWindowController: SettingsWindowController?
    private var shortcutsWindowController: ShortcutsWindowController?
    private let settingsStore = SettingsStore(persistence: UserDefaults.standard)

    // Sparkle: created at init so the updater starts with the app and can
    // schedule its background checks (SUEnableAutomaticChecks defaults on).
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set the icon explicitly so the About panel and system dialogs show
        // it even when LaunchServices serves a stale cached icon for this
        // (frequently re-signed) debug bundle.
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = icon
        }

        let settings = settingsStore.load()
        let coordinator = SessionCoordinator(
            settings: settings,
            snapshotter: ScreenSnapshotter(),
            permissions: PermissionCoordinator(),
            liveStream: LiveStreamController(),
            recorder: ScreenRecorderController()
        )
        self.coordinator = coordinator

        let settingsWindow = SettingsWindowController(store: settingsStore, updater: updaterController.updater) { [weak self] newSettings in
            self?.coordinator?.applySettings(newSettings)
            self?.applyHotkeys(newSettings)
        }
        settingsWindowController = settingsWindow

        let shortcutsWindow = ShortcutsWindowController(store: settingsStore)
        shortcutsWindowController = shortcutsWindow

        statusItemController = StatusItemController(
            onZoom: { coordinator.trigger(.toggleZoom) },
            onLiveZoom: { coordinator.trigger(.toggleLiveZoom) },
            onDraw: { coordinator.trigger(.toggleDraw) },
            onBreak: { coordinator.trigger(.toggleBreak) },
            onRecord: { coordinator.trigger(.toggleRecord) },
            onSnip: { coordinator.trigger(.snip) },
            onShortcuts: { shortcutsWindow.show() },
            onSettings: { settingsWindow.show() },
            onCheckForUpdates: { [weak self] in self?.updaterController.checkForUpdates(nil) }
        )
        coordinator.onRecordingStateChange = { [weak self] recording in
            self?.statusItemController?.setRecording(recording)
        }

        let registrar = HotkeyRegistrar(onHotkey: { action in
            coordinator.trigger(action)
        })
        hotkeyRegistrar = registrar
        applyHotkeys(settings)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                coordinator.send(.displayConfigurationChanged)
            }
        }
    }

    private func applyHotkeys(_ settings: Settings) {
        guard let registrar = hotkeyRegistrar else { return }
        let failed = registrar.apply(settings.hotkeys)
        statusItemController?.setWarning(!failed.isEmpty)
        if !failed.isEmpty {
            NSLog("hotkey registration failed for: \(failed.map(\.rawValue).joined(separator: ", "))")
        }
    }
}
