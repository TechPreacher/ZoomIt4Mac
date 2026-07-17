import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onZoom: () -> Void
    private let onLiveZoom: () -> Void
    private let onDraw: () -> Void
    private let onBreak: () -> Void
    private let onRecord: () -> Void
    private let onSnip: () -> Void
    private let onOcrSnip: () -> Void
    private let onShortcuts: () -> Void
    private let onSettings: () -> Void
    private let onCheckForUpdates: () -> Void
    private var recordItem: NSMenuItem!

    init(
        onZoom: @escaping () -> Void,
        onLiveZoom: @escaping () -> Void,
        onDraw: @escaping () -> Void,
        onBreak: @escaping () -> Void,
        onRecord: @escaping () -> Void,
        onSnip: @escaping () -> Void,
        onOcrSnip: @escaping () -> Void,
        onShortcuts: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.onZoom = onZoom
        self.onLiveZoom = onLiveZoom
        self.onDraw = onDraw
        self.onBreak = onBreak
        self.onRecord = onRecord
        self.onSnip = onSnip
        self.onOcrSnip = onOcrSnip
        self.onShortcuts = onShortcuts
        self.onSettings = onSettings
        self.onCheckForUpdates = onCheckForUpdates
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "plus.magnifyingglass",
            accessibilityDescription: "ZoomIt4Mac"
        )

        let menu = NSMenu()
        menu.addItem(makeItem("Zoom", action: #selector(zoomTapped), key: "1"))
        menu.addItem(makeItem("Live Zoom", action: #selector(liveZoomTapped), key: "4"))
        menu.addItem(makeItem("Draw", action: #selector(drawTapped), key: "2"))
        menu.addItem(makeItem("Break Timer", action: #selector(breakTapped), key: "3"))
        recordItem = makeItem("Start Recording", action: #selector(recordTapped), key: "5")
        menu.addItem(recordItem)
        menu.addItem(makeItem("Snip", action: #selector(snipTapped), key: "6"))
        menu.addItem(makeItem("OCR Snip", action: #selector(ocrSnipTapped), key: "6", modifiers: [.control, .option]))
        menu.addItem(.separator())
        menu.addItem(makeItem("Keyboard Shortcuts…", action: #selector(shortcutsTapped), key: ""))
        menu.addItem(makeItem("Settings…", action: #selector(settingsTapped), key: ","))
        menu.addItem(makeItem("Check for Updates…", action: #selector(checkForUpdatesTapped), key: ""))
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About ZoomIt4Mac", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        about.target = NSApp
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit ZoomIt4Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags = [.control]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key == "," ? [.command] : modifiers
        item.target = self
        return item
    }

    @objc private func zoomTapped() { onZoom() }
    @objc private func liveZoomTapped() { onLiveZoom() }
    @objc private func drawTapped() { onDraw() }
    @objc private func breakTapped() { onBreak() }
    @objc private func recordTapped() { onRecord() }
    @objc private func snipTapped() { onSnip() }
    @objc private func ocrSnipTapped() { onOcrSnip() }
    @objc private func shortcutsTapped() { onShortcuts() }
    @objc private func settingsTapped() { onSettings() }
    @objc private func checkForUpdatesTapped() { onCheckForUpdates() }

    private var warningOn = false
    private var recordingOn = false

    func setWarning(_ on: Bool) {
        warningOn = on
        updateIcon()
    }

    func setRecording(_ on: Bool) {
        recordingOn = on
        recordItem.title = on ? "Stop Recording" : "Start Recording"
        updateIcon()
    }

    private func updateIcon() {
        let (symbol, description): (String, String) = if warningOn {
            ("exclamationmark.triangle", "ZoomIt4Mac — hotkey problem")
        } else if recordingOn {
            ("record.circle", "ZoomIt4Mac — recording")
        } else {
            ("plus.magnifyingglass", "ZoomIt4Mac")
        }
        var image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        if recordingOn && !warningOn {
            // contentTintColor is unreliable on a non-template SF Symbol;
            // bake the red tint into the image itself via a palette config.
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            image = image?.withSymbolConfiguration(config)
            image?.isTemplate = false
        }
        statusItem.button?.image = image
    }
}
