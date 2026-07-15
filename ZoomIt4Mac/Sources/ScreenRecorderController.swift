import AppKit
import AVFoundation
@preconcurrency import ScreenCaptureKit
import ZoomItCore

@MainActor
protocol ScreenRecording: AnyObject {
    func start(
        displayID: CGDirectDisplayID,
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
                let pixelSize = CGSize(
                    width: CGFloat(display.width) * scale,
                    height: CGFloat(display.height) * scale
                )
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
                    systemAudio: systemAudio,
                    microphone: micEnabled
                )
                let output = RecorderOutput(writer: writer, onStopped: { [weak self] in
                    guard let self, gen == self.generation else { return }
                    // Salvage what was written (partial file still revealed
                    // if non-empty), then report the failure.
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
                    Task { try? await stream.stopCapture() }
                    await writer.cancel()
                    return
                }
                if let micSession {
                    // startRunning blocks; keep it off the main actor.
                    // AVCaptureSession isn't Sendable on this SDK; safe here
                    // because no other actor touches this instance until it
                    // reaches self.micSession below (see LiveStreamController
                    // for the same pattern).
                    nonisolated(unsafe) let session = micSession
                    Task.detached { session.startRunning() }
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
                // AVCaptureSession isn't Sendable on this SDK; safe here
                // because `mic` is a local capture of the outgoing session,
                // already detached from `self.micSession` above.
                nonisolated(unsafe) let mic = mic
                Task.detached { mic.stopRunning() }
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
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Recording \(formatter.string(from: Date())).mp4"
        return directory.appendingPathComponent(name)
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

    init(url: URL, videoSize: CGSize, systemAudio: Bool, microphone: Bool) throws {
        self.url = url
        self.writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height),
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
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
        writer.startWriting()
    }

    /// Video drives the session clock: audio arriving before the first video
    /// frame is dropped so the file never starts with black-frame silence.
    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        if !sessionStarted && !cancelled && writer.status == .writing {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            sessionStarted = true
        }
        let ready = sessionStarted && !cancelled && videoInput.isReadyForMoreMediaData
        lock.unlock()
        if ready { videoInput.append(sampleBuffer) }
    }

    func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        append(sampleBuffer, to: systemAudioInput)
    }

    func appendMic(_ sampleBuffer: CMSampleBuffer) {
        append(sampleBuffer, to: micInput)
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?) {
        lock.lock()
        let ready = sessionStarted && !cancelled && (input?.isReadyForMoreMediaData ?? false)
        lock.unlock()
        if ready { input?.append(sampleBuffer) }
    }

    /// Finalize; returns the URL when anything was written, else deletes the
    /// empty container and returns nil.
    func finish() async -> URL? {
        // NSLock.lock()/unlock() are unavailable from async contexts on the
        // newer SDK (no suspension may occur while holding the lock); the
        // mutation is isolated in this synchronous helper instead.
        let hadContent = markCancelledAndCheckContent()
        guard hadContent, writer.status == .writing else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        videoInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        micInput?.markAsFinished()
        await writer.finishWriting()
        return url
    }

    func cancel() async {
        markCancelled()
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }

    private func markCancelledAndCheckContent() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let hadContent = sessionStarted && !cancelled
        cancelled = true
        return hadContent
    }

    private func markCancelled() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
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
