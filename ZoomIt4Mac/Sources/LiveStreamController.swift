import AppKit
import CoreImage
// @preconcurrency: SCShareableContent is not Sendable in the macOS 15 SDK
// (Xcode 16.x, used by CI); returning it from the nonisolated async fetch
// into this MainActor task is otherwise a Swift 6 isolation error there.
@preconcurrency import ScreenCaptureKit
import ZoomItCore

@MainActor
protocol LiveStreaming: AnyObject {
    func start(
        displayID: CGDirectDisplayID,
        excluding windows: [NSWindow],
        onFrame: @escaping @MainActor (IOSurface) -> Void,
        onError: @escaping @MainActor (CaptureFailure) -> Void
    )
    func stop()
    func latestFrameImage() -> CGImage?
}

@MainActor
final class LiveStreamController: LiveStreaming {
    private var stream: SCStream?
    private var output: LiveFrameOutput?
    private var latestSurface: IOSurface?
    private let ciContext = CIContext()
    private var generation = 0

    func start(
        displayID: CGDirectDisplayID,
        excluding windows: [NSWindow],
        onFrame: @escaping @MainActor (IOSurface) -> Void,
        onError: @escaping @MainActor (CaptureFailure) -> Void
    ) {
        stop()
        let gen = generation
        let excludedNumbers = Set(windows.map { CGWindowID($0.windowNumber) })
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    if gen == self.generation {
                        onError(.captureError)
                    }
                    return
                }
                // Overlay windows are sharingType .readOnly (so screen recordings can
                // capture annotations), which means they DO appear in shareable
                // content — this explicit exclusion is the active feedback-loop
                // protection for the live-zoom stream.
                let excluded = content.windows.filter { excludedNumbers.contains($0.windowID) }
                let filter = SCContentFilter(display: display, excludingWindows: excluded)

                let config = SCStreamConfiguration()
                let scale = self.scaleFactor(for: displayID)
                config.width = Int(CGFloat(display.width) * scale)
                config.height = Int(CGFloat(display.height) * scale)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.queueDepth = 3
                config.showsCursor = true
                config.pixelFormat = kCVPixelFormatType_32BGRA

                let output = LiveFrameOutput(
                    handler: { [weak self] surface in
                        guard let self, gen == self.generation else { return }
                        self.latestSurface = surface
                        onFrame(surface)
                    },
                    onStopped: { [weak self] in
                        guard let self, gen == self.generation else { return }
                        onError(.captureError)
                    }
                )
                let stream = SCStream(filter: filter, configuration: config, delegate: output)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
                try await stream.startCapture()
                guard gen == self.generation else {
                    Task { try? await stream.stopCapture() }
                    return
                }
                self.stream = stream
                self.output = output
            } catch {
                if gen == self.generation {
                    onError(.captureError)
                }
            }
        }
    }

    func stop() {
        generation += 1
        let stopping = stream
        stream = nil
        output = nil
        latestSurface = nil
        Task { try? await stopping?.stopCapture() }
    }

    func latestFrameImage() -> CGImage? {
        guard let latestSurface else { return nil }
        let image = CIImage(ioSurface: latestSurface)
        return ciContext.createCGImage(image, from: image.extent)
    }

    private func scaleFactor(for displayID: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID), mode.width > 0 else { return 1 }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}

/// Receives stream frames on a background queue and hops them to MainActor.
/// Also acts as the stream's delegate so mid-session stream death (permission
/// revoked, SCK/WindowServer errors) is detected instead of silently freezing
/// the view.
private final class LiveFrameOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.corti.zoomit.live-frames")
    private let handler: @MainActor (IOSurface) -> Void
    private let onStopped: @MainActor () -> Void

    init(handler: @escaping @MainActor (IOSurface) -> Void, onStopped: @escaping @MainActor () -> Void) {
        self.handler = handler
        self.onStopped = onStopped
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        // IOSurface is not Sendable in the macOS 15 SDK (Xcode 16.x, CI),
        // but handing it across threads is safe here: IOSurface is a
        // cross-process-shareable GPU object and the main actor only reads it.
        nonisolated(unsafe) let surface = unsafeBitCast(surfaceRef, to: IOSurface.self)
        Task { @MainActor [handler] in
            handler(surface)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [onStopped] in
            onStopped()
        }
    }
}
