import CoreGraphics
import ScreenCaptureKit
import ZoomItCore

protocol Snapshotting: Sendable {
    /// Capture one frozen frame per display, keyed by display ID.
    func captureAllDisplays() async -> Result<[CGDirectDisplayID: CGImage], CaptureFailure>
    /// Capture a single display as the user sees it — overlay windows are
    /// sharingType .readOnly, so annotations are included.
    func captureDisplay(_ displayID: CGDirectDisplayID) async -> Result<CGImage, CaptureFailure>
}

struct ScreenSnapshotter: Snapshotting {
    func captureAllDisplays() async -> Result<[CGDirectDisplayID: CGImage], CaptureFailure> {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // SCShareableContent fetch fails when Screen Recording is not granted.
            return .failure(.permissionDenied)
        }

        var images: [CGDirectDisplayID: CGImage] = [:]
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(CGFloat(display.width) * scaleFactor(for: display.displayID))
            config.height = Int(CGFloat(display.height) * scaleFactor(for: display.displayID))
            config.showsCursor = false
            do {
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config
                )
                images[display.displayID] = image
            } catch {
                return .failure(.captureError)
            }
        }
        guard !images.isEmpty else { return .failure(.captureError) }
        return .success(images)
    }

    func captureDisplay(_ displayID: CGDirectDisplayID) async -> Result<CGImage, CaptureFailure> {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            return .failure(.permissionDenied)
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            return .failure(.captureError)
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scaleFactor(for: displayID))
        config.height = Int(CGFloat(display.height) * scaleFactor(for: displayID))
        config.showsCursor = false
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
            return .success(image)
        } catch {
            return .failure(.captureError)
        }
    }

    private func scaleFactor(for displayID: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID), mode.width > 0 else { return 1 }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}
