import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onZoom: () -> Void
    private let onDraw: () -> Void
    private let onSettings: () -> Void

    init(onZoom: @escaping () -> Void, onDraw: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.onZoom = onZoom
        self.onDraw = onDraw
        self.onSettings = onSettings
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "plus.magnifyingglass",
            accessibilityDescription: "ZoomIt4Mac"
        )

        let menu = NSMenu()
        menu.addItem(makeItem("Zoom", action: #selector(zoomTapped), key: "1"))
        menu.addItem(makeItem("Draw", action: #selector(drawTapped), key: "2"))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", action: #selector(settingsTapped), key: ","))
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About ZoomIt4Mac", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        about.target = NSApp
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit ZoomIt4Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key == "," ? [.command] : [.control]
        item.target = self
        return item
    }

    @objc private func zoomTapped() { onZoom() }
    @objc private func drawTapped() { onDraw() }
    @objc private func settingsTapped() { onSettings() }

    func setWarning(_ on: Bool) {
        statusItem.button?.image = NSImage(
            systemSymbolName: on ? "exclamationmark.triangle" : "plus.magnifyingglass",
            accessibilityDescription: on ? "ZoomIt4Mac — hotkey problem" : "ZoomIt4Mac"
        )
    }
}
