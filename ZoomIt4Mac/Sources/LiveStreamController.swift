import AppKit
import CoreImage
import ScreenCaptureKit
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

                let output = LiveFrameOutput { [weak self] surface in
                    guard let self, gen == self.generation else { return }
                    self.latestSurface = surface
                    onFrame(surface)
                }
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
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
private final class LiveFrameOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.corti.zoomit.live-frames")
    private let handler: @MainActor (IOSurface) -> Void

    init(handler: @escaping @MainActor (IOSurface) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        let surface = unsafeBitCast(surfaceRef, to: IOSurface.self)
        Task { @MainActor [handler] in
            handler(surface)
        }
    }
}
