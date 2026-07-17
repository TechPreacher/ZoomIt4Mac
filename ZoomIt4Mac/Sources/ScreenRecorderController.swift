import AppKit
import AVFoundation
@preconcurrency import ScreenCaptureKit
import ZoomItCore

@MainActor
protocol ScreenRecording: AnyObject {
    func start(
        displayID: CGDirectDisplayID,
        codec: RecordingCodec,
        region: CGRect?,
        microphone: Bool,
        systemAudio: Bool,
        onError: @escaping @MainActor (CaptureFailure) -> Void
    )
    func stop(completion: @escaping @MainActor (URL?) -> Void)
}

@MainActor
final class ScreenRecorderController: ScreenRecording {
    private var generation = 0
    private var stream: SCStream?
    private var output: RecorderOutput?
    private var micSession: AVCaptureSession?
    private var writer: RecordingWriter?

    func start(
        displayID: CGDirectDisplayID,
        codec: RecordingCodec,
        region: CGRect?,
        microphone: Bool,
        systemAudio: Bool,
        onError: @escaping @MainActor (CaptureFailure) -> Void
    ) {
        teardown(completion: nil)
        generation += 1
        let gen = generation

        Task {
            // Microphone authorization may suspend for the system prompt.
            var micEnabled = microphone
            if micEnabled {
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized:
                    break
                case .notDetermined:
                    micEnabled = await AVCaptureDevice.requestAccess(for: .audio)
                default:
                    micEnabled = false
                }
                if microphone && !micEnabled {
                    NSSound.beep()
                    NSLog("microphone unavailable; recording without mic audio")
                }
            }
            guard gen == self.generation else { return }

            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard gen == self.generation else { return }
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    onError(.captureError)
                    return
                }

                // Exclude nothing: overlays are .readOnly on purpose so
                // zoom/draw activity is part of the recording.
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                let scale = self.scaleFactor(for: displayID)
                let pixelSize: CGSize
                if let region {
                    // region is already in SCK sourceRect space (display-
                    // relative points, top-left origin), clamped by the
                    // coordinator via RecordingGeometry.
                    config.sourceRect = region
                    pixelSize = RecordingGeometry.outputPixelSize(sourceRect: region, scale: scale)
                } else {
                    pixelSize = CGSize(
                        width: CGFloat(display.width) * scale,
                        height: CGFloat(display.height) * scale
                    )
                }
                config.width = Int(pixelSize.width)
                config.height = Int(pixelSize.height)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.queueDepth = 6
                config.showsCursor = true
                config.capturesAudio = systemAudio
                config.pixelFormat = kCVPixelFormatType_32BGRA

                let url = try Self.makeOutputURL()
                let writer = try RecordingWriter(
                    url: url,
                    videoSize: pixelSize,
                    codec: codec,
                    systemAudio: systemAudio,
                    microphone: micEnabled
                )
                let output = RecorderOutput(writer: writer, onStopped: { [weak self] in
                    guard let self, gen == self.generation else { return }
                    // Salvage what was written (partial file still revealed
                    // if non-empty), then report the failure. Unlike the
                    // coordinator's normal stop path this reveal is not
                    // deferred to .idle — it only fires on mid-recording
                    // stream death, which is rare enough to accept the
                    // (unlikely) focus-theft risk here.
                    self.stop { url in
                        if let url {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    onError(.captureError)
                })

                let stream = SCStream(filter: filter, configuration: config, delegate: output)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.videoQueue)
                if systemAudio {
                    try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.audioQueue)
                }

                var micSession: AVCaptureSession?
                if micEnabled {
                    if let device = AVCaptureDevice.default(for: .audio),
                       let input = try? AVCaptureDeviceInput(device: device) {
                        let session = AVCaptureSession()
                        if session.canAddInput(input) { session.addInput(input) }
                        let micOutput = AVCaptureAudioDataOutput()
                        micOutput.setSampleBufferDelegate(output, queue: output.micQueue)
                        if session.canAddOutput(micOutput) { session.addOutput(micOutput) }
                        micSession = session
                    } else {
                        NSSound.beep()
                        NSLog("no audio input device; recording without mic audio")
                    }
                }

                try await stream.startCapture()
                guard gen == self.generation else {
                    Task {
                        try? await stream.stopCapture()
                        await writer.cancel()
                    }
                    return
                }
                if let micSession {
                    // startRunning blocks; keep it off the main actor.
                    // AVCaptureSession isn't Sendable (and CI's older compiler
                    // also rejects nonisolated(unsafe) captures in detached
                    // closures) — box it. Safe: no other actor touches this
                    // instance until it reaches self.micSession below.
                    let boxed = UncheckedSendable(value: micSession)
                    Task.detached { boxed.value.startRunning() }
                }
                self.stream = stream
                self.output = output
                self.writer = writer
                self.micSession = micSession
            } catch {
                guard gen == self.generation else { return }
                onError(.captureError)
            }
        }
    }

    func stop(completion: @escaping @MainActor (URL?) -> Void) {
        teardown(completion: completion)
    }

    private func teardown(completion: (@MainActor (URL?) -> Void)?) {
        generation += 1
        let stream = self.stream
        let writer = self.writer
        let mic = self.micSession
        self.stream = nil
        self.output = nil
        self.writer = nil
        self.micSession = nil
        Task {
            if let mic {
                // AVCaptureSession isn't Sendable — box it (see start()).
                // Awaited so the mic queue is fully drained before the writer
                // finalizes below (otherwise a late mic append can race
                // markAsFinished).
                let boxed = UncheckedSendable(value: mic)
                await Task.detached { boxed.value.stopRunning() }.value
            }
            try? await stream?.stopCapture()
            let url = await writer?.finish()
            completion?(url)
        }
    }

    private func scaleFactor(for displayID: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID), mode.width > 0 else { return 1 }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }

    private static func makeOutputURL() throws -> URL {
        let directory = FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZoomIt4Mac", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let baseName = "Recording \(formatter.string(from: Date()))"
        var candidate = directory.appendingPathComponent("\(baseName).mp4")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) (\(suffix)).mp4")
            suffix += 1
        }
        return candidate
    }
}

/// Thread-safe AVAssetWriter wrapper. Appends arrive on the recorder's
/// background queues; AVAssetWriter supports concurrent appends to distinct
/// inputs, and the session start is guarded by a lock.
private final class RecordingWriter: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let micInput: AVAssetWriterInput?
    private let lock = NSLock()
    private var sessionStarted = false
    private var cancelled = false
    let url: URL

    init(url: URL, videoSize: CGSize, codec: RecordingCodec, systemAudio: Bool, microphone: Bool) throws {
        self.url = url
        self.writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        // Explicit compression properties: without them VideoToolbox picks a
        // dimension-scaled default bitrate that is ~2× what screen content
        // needs (see docs/superpowers/specs/2026-07-17-recording-codec-design.md).
        let frameRate = 30 // matches config.minimumFrameInterval in start()
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: codec.averageBitRate(
                width: Int(videoSize.width),
                height: Int(videoSize.height),
                frameRate: frameRate
            ),
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height),
            AVVideoCompressionPropertiesKey: compression,
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
        ]
        if systemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            systemAudioInput = input
        } else {
            systemAudioInput = nil
        }
        if microphone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            micInput = input
        } else {
            micInput = nil
        }
        guard writer.startWriting() else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }

    /// Video drives the session clock: audio arriving before the first video
    /// frame is dropped so the file never starts with black-frame silence.
    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        if !sessionStarted && !cancelled && writer.status == .writing {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            sessionStarted = true
        }
        // Append happens inside the lock so it can never land after
        // finish()/cancel() flip `cancelled` and call markAsFinished()/
        // cancelWriting() on the inputs — that ordering is what avoids the
        // NSInternalInconsistencyException from appending to a finished
        // input. Three producer queues at 30fps + audio make the resulting
        // lock contention negligible.
        let ready = sessionStarted && !cancelled && videoInput.isReadyForMoreMediaData
        if ready { videoInput.append(sampleBuffer) }
        lock.unlock()
    }

    func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        append(sampleBuffer, to: systemAudioInput)
    }

    func appendMic(_ sampleBuffer: CMSampleBuffer) {
        append(sampleBuffer, to: micInput)
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?) {
        lock.lock()
        // See appendVideo(_:) above: append stays inside the lock so it's
        // fully serialized against finish()/cancel()'s state flip.
        let ready = sessionStarted && !cancelled && (input?.isReadyForMoreMediaData ?? false)
        if ready { input?.append(sampleBuffer) }
        lock.unlock()
    }

    /// Finalize; returns the URL when anything was written, else deletes the
    /// empty container and returns nil.
    func finish() async -> URL? {
        // NSLock.lock()/unlock() are unavailable from async contexts on the
        // newer SDK (no suspension may occur while holding the lock); the
        // mutation is isolated in this synchronous helper instead. Flipping
        // `cancelled` and calling markAsFinished()/cancelWriting() happen
        // under the same lock as the appends above, so any in-flight append
        // either completed before this runs or observes `cancelled` and is
        // skipped — never both.
        let hadContent = finalizeInputsLocked()
        guard hadContent else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        await writer.finishWriting()
        return url
    }

    func cancel() async {
        // NSLock.lock()/unlock() are unavailable from async contexts (see
        // finish() above); the flip + cancelWriting() happen together in
        // this synchronous helper so they stay serialized against appends.
        cancelInputsLocked()
        try? FileManager.default.removeItem(at: url)
    }

    private func cancelInputsLocked() {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return }
        cancelled = true
        writer.cancelWriting()
    }

    private func finalizeInputsLocked() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let hadContent = sessionStarted && !cancelled && writer.status == .writing
        cancelled = true
        if hadContent {
            videoInput.markAsFinished()
            systemAudioInput?.markAsFinished()
            micInput?.markAsFinished()
        } else {
            writer.cancelWriting()
        }
        return hadContent
    }
}

/// Receives stream/mic buffers on background queues and forwards them to the
/// writer; also acts as SCStreamDelegate for mid-recording stream death.
private final class RecorderOutput: NSObject, SCStreamOutput, SCStreamDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let videoQueue = DispatchQueue(label: "com.corti.zoomit.record-video")
    let audioQueue = DispatchQueue(label: "com.corti.zoomit.record-audio")
    let micQueue = DispatchQueue(label: "com.corti.zoomit.record-mic")
    private let writer: RecordingWriter
    private let onStopped: @MainActor () -> Void

    init(writer: RecordingWriter, onStopped: @escaping @MainActor () -> Void) {
        self.writer = writer
        self.onStopped = onStopped
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            // Only complete frames carry image buffers.
            guard sampleBuffer.imageBuffer != nil else { return }
            writer.appendVideo(sampleBuffer)
        case .audio:
            writer.appendSystemAudio(sampleBuffer)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [onStopped] in
            onStopped()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        writer.appendMic(sampleBuffer)
    }
}

/// Explicit Sendable box for values that must cross an isolation boundary
/// where safety is established by ownership discipline, not the type system.
/// Works on all supported compiler versions, unlike nonisolated(unsafe)
/// captures in detached closures (rejected by CI's Xcode 16.4).
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}
