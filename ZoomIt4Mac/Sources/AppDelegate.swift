import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(
            onZoom: { NSLog("zoom requested") },
            onDraw: { NSLog("draw requested") },
            onSettings: { NSLog("settings requested") }
        )
    }
}
