import AppKit
import SwiftUI

private struct RecordingNoticeView: View {
    let stopComboLabel: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen recording is starting…")
                    .font(.headline)
                Text("Press \(stopComboLabel) again to stop")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Small centered HUD shown between ⌃5 and the actual capture start.
/// Non-activating and mouse-transparent so it never steals key status from
/// mode overlays; dismissed before the stream starts, so it is never in the
/// recording itself.
@MainActor
final class RecordingNoticeController {
    private var panel: NSPanel?

    func show(on screen: NSScreen, stopComboLabel: String) {
        dismiss()
        let view = NSHostingView(rootView: RecordingNoticeView(stopComboLabel: stopComboLabel))
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
