# Screen Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Screen Recording (⌃5): record the active display — including ZoomIt4Mac's own zoom/draw activity — to .mp4, with independent microphone and system-audio toggles.

**Architecture:** Recording is orthogonal to modes: `SessionStateMachine.isRecording` flag handled pre-dispatch (⌃5 toggles in any state; mode changes never touch it; display change stops-and-saves). Effects `.startRecording/.stopRecording` drive a shell `ScreenRecorderController` (SCStream → AVAssetWriter, H.264+AAC; mic via separate AVCaptureSession on macOS 14). Overlays become `sharingType = .readOnly` so annotations appear in recordings; Live Zoom's explicit window exclusion becomes the real feedback-loop protection. Spec: `docs/superpowers/specs/2026-07-15-screen-recording-design.md`.

**Tech Stack:** Swift 6, ScreenCaptureKit, AVFoundation (AVAssetWriter, AVCaptureSession), existing stack.

## Global Constraints

- Branch `feature/screen-recording`. All 137 existing tests stay green; count only grows.
- ZoomItCore never imports AppKit; no Date/Timer in core (timestamps/dates only in shell).
- Default hotkey **⌃5 = KeyCombo(keyCode: 23, .control)**; defaults stay conflict-free.
- `RecordingConfiguration` defaults: `recordMicrophone = true`, `recordSystemAudio = false`. Old persisted Settings JSON (no `recording` key) must decode to defaults — pinned by strip-the-key test.
- ⌃5 is consumed pre-dispatch: it toggles recording and NEVER exits or enters a mode. Esc and mode transitions NEVER stop recording. `displayConfigurationChanged` stops recording (stop-and-save) AND does its existing mode force-exit, `.stopRecording` first in the effect array.
- Output: `~/Movies/ZoomIt4Mac/Recording yyyy-MM-dd 'at' HH.mm.ss.mp4`, H.264 + AAC, 30 fps, native pixel size; Finder reveals the file on stop.
- Mic denial degrades to no-mic recording (beep + log), never blocks. Screen Recording permission missing → deferred prompt + `.recordingFailed` (existing live-zoom pattern).
- CI runs Xcode 16.4 (macOS 15 SDK) with missing Sendable annotations — use `@preconcurrency import ScreenCaptureKit` and mark unavoidable cross-actor transfers `nonisolated(unsafe)` with a comment, as in LiveStreamController.
- Commits: trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Test command: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'`. New files → `xcodegen` first.

## File Structure

```
ZoomItCore/Sources/RecordingConfiguration.swift  settings sub-struct (new)
ZoomItCore/Sources/Settings.swift                gains recording field + migration (modify)
ZoomItCore/Sources/HotkeyConfiguration.swift     toggleRecord + ⌃5 default (modify)
ZoomItCore/Sources/SessionStateMachine.swift     isRecording flag, effects, pre-dispatch (modify)
ZoomItCore/Tests/RecordingConfigurationTests.swift (new)
ZoomItCore/Tests/SettingsTests.swift             migration test appended (modify)
ZoomItCore/Tests/SessionStateMachineTests.swift  recording suite appended (modify)
ZoomIt4Mac/Sources/ScreenRecorderController.swift  SCStream+AVAssetWriter recorder (new)
ZoomIt4Mac/Sources/SessionCoordinator.swift      effect handlers + indicator sync (modify)
ZoomIt4Mac/Sources/StatusItemController.swift    record menu item + red indicator (modify)
ZoomIt4Mac/Sources/OverlayWindowController.swift sharingType .readOnly (modify)
ZoomIt4Mac/Sources/LiveStreamController.swift    exclusion comment rewrite (modify)
ZoomIt4Mac/Sources/AppDelegate.swift             recorder injection + callbacks (modify)
ZoomIt4Mac/Sources/SettingsWindow.swift          Recording section + hotkey row (modify)
ZoomIt4Mac/Sources/ShortcutsWindow.swift         recording row (modify)
project.yml                                      NSMicrophoneUsageDescription (modify)
README.md                                        feature bullet + permissions (modify)
```

---

### Task 1: Core — RecordingConfiguration, settings migration, ⌃5 default

**Files:**
- Create: `ZoomItCore/Sources/RecordingConfiguration.swift`
- Modify: `ZoomItCore/Sources/Settings.swift`, `ZoomItCore/Sources/HotkeyConfiguration.swift`
- Test: `ZoomItCore/Tests/RecordingConfigurationTests.swift` (new), `ZoomItCore/Tests/SettingsTests.swift` (append)

**Interfaces:**
- Produces:
  - `RecordingConfiguration: Codable, Equatable, Sendable` — `recordMicrophone: Bool`, `recordSystemAudio: Bool`, `static let default` (true / false)
  - `Settings.recording: RecordingConfiguration` — decodes to `.default` when the key is missing
  - `HotkeyAction.toggleRecord` (raw `toggleRecord`); default ⌃5 = KeyCombo(keyCode: 23, modifiers: .control)

- [ ] **Step 1: Write the failing test**

`ZoomItCore/Tests/RecordingConfigurationTests.swift`:
```swift
import Testing
import Foundation
import ZoomItCore

struct RecordingConfigurationTests {
    @Test func defaults() {
        let c = RecordingConfiguration.default
        #expect(c.recordMicrophone)
        #expect(!c.recordSystemAudio)
    }

    @Test func codableRoundTrip() throws {
        var c = RecordingConfiguration.default
        c.recordMicrophone = false
        c.recordSystemAudio = true
        let back = try JSONDecoder().decode(RecordingConfiguration.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }

    @Test func defaultRecordHotkeyIsCtrl5() {
        #expect(HotkeyConfiguration.default.combo(for: .toggleRecord) == KeyCombo(keyCode: 23, modifiers: .control))
        #expect(HotkeyConfiguration.default.conflictingCombos().isEmpty)
    }
}
```

Append to `ZoomItCore/Tests/SettingsTests.swift`:
```swift
struct SettingsRecordingMigrationTests {
    @Test func jsonWithoutRecordingKeyDecodesToDefaults() throws {
        var s = Settings.default
        s.penColor = .blue
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        object.removeValue(forKey: "recording")
        let p = FakePersistence()
        p.storage["zoomit.settings.v1"] = try JSONSerialization.data(withJSONObject: object)
        let loaded = SettingsStore(persistence: p).load()
        #expect(loaded.penColor == .blue)
        #expect(loaded.recording == .default)
    }

    @Test func recordingRoundTripsThroughStore() {
        let store = SettingsStore(persistence: FakePersistence())
        var s = Settings.default
        s.recording.recordSystemAudio = true
        s.recording.recordMicrophone = false
        store.save(s)
        #expect(store.load().recording == s.recording)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen && xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `cannot find 'RecordingConfiguration' in scope`.

- [ ] **Step 3: Write minimal implementation**

`ZoomItCore/Sources/RecordingConfiguration.swift`:
```swift
public struct RecordingConfiguration: Codable, Equatable, Sendable {
    public var recordMicrophone: Bool
    public var recordSystemAudio: Bool

    public static let `default` = RecordingConfiguration(
        recordMicrophone: true,
        recordSystemAudio: false
    )
}
```

`ZoomItCore/Sources/HotkeyConfiguration.swift`:
```swift
public enum HotkeyAction: String, Codable, CaseIterable, Hashable, Sendable {
    case toggleZoom, toggleDraw, toggleBreak, toggleLiveZoom, toggleRecord
}
```
and in `default`:
```swift
        .toggleRecord: KeyCombo(keyCode: 23, modifiers: .control),    // ⌃5
```

`ZoomItCore/Sources/Settings.swift` — Settings currently declares an explicit `CodingKeys` enum, memberwise `init`, custom `init(from:)`, and explicit `encode(to:)` (added during the break-timer migration). Extend all four:
- Add stored property `public var recording: RecordingConfiguration` (after `breakTimer`).
- Add `case recording` to `CodingKeys`.
- Memberwise init: add `recording: RecordingConfiguration` parameter; assign it; update `Settings.default` to pass `recording: .default`.
- `init(from:)`: `recording = try container.decodeIfPresent(RecordingConfiguration.self, forKey: .recording) ?? .default`
- `encode(to:)`: `try container.encode(recording, forKey: .recording)`
- `sanitized()` needs no change (booleans).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -5`
Expected: TEST SUCCEEDED (137 + 5 new).

- [ ] **Step 5: Commit**

```bash
git add ZoomItCore
git commit -m "Add recording configuration to settings with migration and ctrl-5 hotkey"
```

---

### Task 2: Core — orthogonal isRecording state

**Files:**
- Modify: `ZoomItCore/Sources/SessionStateMachine.swift`, `ZoomIt4Mac/Sources/SessionCoordinator.swift` (compile-forced placeholder arms only)
- Test: `ZoomItCore/Tests/SessionStateMachineTests.swift` (append)

**Interfaces:**
- Consumes: `HotkeyAction.toggleRecord` (Task 1)
- Produces:
  - `SessionStateMachine.isRecording: Bool` (public read-only, default false)
  - `SessionEvent.recordingFailed`
  - `SessionEffect.startRecording`, `.stopRecording`
  - Pre-dispatch semantics: `hotkey(.toggleRecord, _, _)` in ANY state flips the flag, returns `[.startRecording]` or `[.stopRecording]`, never touches `state`; `.recordingFailed` clears the flag + `[.notifyCaptureFailure]` only when recording, else `[]`; `displayConfigurationChanged` prepends `.stopRecording` (and clears the flag) when recording, keeping its existing per-state behavior otherwise.

- [ ] **Step 1: Write the failing test**

Append to `ZoomItCore/Tests/SessionStateMachineTests.swift`:
```swift
struct SessionRecordingTests {
    @Test func toggleStartsAndStopsFromIdle() {
        var m = machine()
        #expect(m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen)) == [.startRecording])
        #expect(m.isRecording)
        #expect(m.state == .idle) // no mode entered
        #expect(m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen)) == [.stopRecording])
        #expect(!m.isRecording)
    }

    @Test func toggleDoesNotDisturbActiveModes() {
        var zoom = zoomedMachine()
        #expect(zoom.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen)) == [.startRecording])
        guard case .zoom = zoom.state else { Issue.record("zoom must survive"); return }

        var draw = drawingMachine()
        draw.handle(.annotationAdded(.line(from: .zero, to: CGPoint(x: 5, y: 5), color: .red, width: 4)))
        draw.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
        #expect(draw.isRecording)
        #expect(draw.drawContext?.canvas.annotations.count == 1) // context preserved

        var brk = breakMachine()
        brk.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
        #expect(brk.isRecording)
        guard case .breakTimer = brk.state else { Issue.record("break must survive"); return }

        var live = liveZoomMachine()
        live.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
        #expect(live.isRecording)
        guard case .liveZoom = live.state else { Issue.record("live zoom must survive"); return }
    }

    @Test func modeChangesLeaveRecordingOn() {
        var m = machine()
        m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
        m.handle(.hotkey(.toggleDraw, mouse: testMouse, screen: testScreen)) // enter draw
        #expect(m.isRecording)
        m.handle(.escape) // exit draw
        #expect(m.isRecording)
        #expect(m.state == .idle)
        m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        m.handle(.captureCompleted) // enter zoom
        #expect(m.isRecording)
        m.handle(.escape)
        #expect(m.isRecording)
    }

    @Test func recordingFailedClearsOnlyWhenRecording() {
        var m = machine()
        #expect(m.handle(.recordingFailed).isEmpty)
        m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
        #expect(m.handle(.recordingFailed) == [.notifyCaptureFailure])
        #expect(!m.isRecording)
        #expect(m.handle(.recordingFailed).isEmpty) // idempotent
    }

    @Test func displayChangeStopsRecordingAndExitsMode() {
        var m = zoomedMachine()
        m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
        let fx = m.handle(.displayConfigurationChanged)
        #expect(fx == [.stopRecording, .dismissOverlays])
        #expect(!m.isRecording)
        #expect(m.state == .idle)
    }

    @Test func displayChangeInIdleWhileRecordingJustStops() {
        var m = machine()
        m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
        #expect(m.handle(.displayConfigurationChanged) == [.stopRecording])
        #expect(!m.isRecording)
    }

    @Test func displayChangeDuringLiveZoomWhileRecordingOrdersEffects() {
        var m = liveZoomMachine()
        m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
        #expect(m.handle(.displayConfigurationChanged) == [.stopRecording, .stopLiveStream, .dismissOverlays])
    }

    @Test func recordHotkeyDoesNotCommitOrExitType() {
        var m = drawingMachine()
        m.handle(.keyCommand(.enterType))
        m.handle(.leftMouseDown(.zero))
        m.handle(.textInput("hi"))
        m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen))
        #expect(m.isRecording)
        guard case .type = m.state else { Issue.record("type must survive"); return }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `type 'SessionEvent' has no member 'recordingFailed'` / `value of type 'SessionStateMachine' has no member 'isRecording'`.

- [ ] **Step 3: Write minimal implementation**

`SessionStateMachine.swift`:
- Add `public private(set) var isRecording = false` next to `state`.
- `SessionEvent`: add `case recordingFailed`. `SessionEffect`: add `case startRecording`, `case stopRecording`.
- Pre-dispatch section of `handle(_:)` — insert BEFORE the existing `displayConfigurationChanged` case and modify that case:
```swift
        switch event {
        case .settingsChanged(let s):
            settings = s.sanitized()
            return []
        case .hotkey(.toggleRecord, _, _):
            isRecording.toggle()
            return isRecording ? [.startRecording] : [.stopRecording]
        case .recordingFailed:
            guard isRecording else { return [] }
            isRecording = false
            return [.notifyCaptureFailure]
        case .displayConfigurationChanged:
            var effects: [SessionEffect] = []
            if isRecording {
                isRecording = false
                effects.append(.stopRecording)
            }
            if case .idle = state { return effects }
            let wasLive = if case .liveZoom = state { true } else { false }
            state = .idle
            effects.append(contentsOf: wasLive ? [.stopLiveStream, .dismissOverlays] : [.dismissOverlays])
            return effects
        default:
            break
        }
```
(Because `.hotkey(.toggleRecord, ...)` is consumed here, it never reaches per-state handlers — no mode exits, no type commit.)

`ZoomIt4Mac/Sources/SessionCoordinator.swift` — the exhaustive `perform(_:)` switch must compile; add placeholder arms (Task 4 replaces):
```swift
        case .startRecording, .stopRecording:
            break // Task 4
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -5`
Expected: TEST SUCCEEDED, all suites.

- [ ] **Step 5: Commit**

```bash
git add ZoomItCore ZoomIt4Mac
git commit -m "Add orthogonal recording state to session machine"
```

---

### Task 3: Shell — ScreenRecorderController + capturability changes

**Files:**
- Create: `ZoomIt4Mac/Sources/ScreenRecorderController.swift`
- Modify: `project.yml` (mic usage string), `ZoomIt4Mac/Sources/OverlayWindowController.swift` (sharingType), `ZoomIt4Mac/Sources/LiveStreamController.swift` (comment rewrite)

Shell task: no unit tests by design; build + suite regression + brief launch smoke.

**Interfaces:**
- Consumes: `CaptureFailure` (core)
- Produces:
  - `protocol ScreenRecording: AnyObject` (@MainActor) — `func start(displayID: CGDirectDisplayID, microphone: Bool, systemAudio: Bool, onError: @escaping @MainActor (CaptureFailure) -> Void)`, `func stop(completion: @escaping @MainActor (URL?) -> Void)`
  - `ScreenRecorderController: ScreenRecording`

- [ ] **Step 1: project.yml — microphone usage description**

In the `ZoomIt4Mac` target's `info.properties`, add:
```yaml
        NSMicrophoneUsageDescription: ZoomIt4Mac records microphone audio in screen recordings when enabled in Settings.
```
Run `xcodegen` after (regenerates Info.plist, which is gitignored).

- [ ] **Step 2: Overlay capturability + live-zoom comment**

`OverlayWindowController.swift` — change:
```swift
        // .readOnly (not .none): recordings must capture our zoom/draw overlays.
        // Live Zoom's stream avoids feedback via its explicit window exclusion.
        window.sharingType = .readOnly
```

`LiveStreamController.swift` — replace the existing comment above the excluded-windows construction with:
```swift
        // Overlay windows are sharingType .readOnly (so screen recordings can
        // capture annotations), which means they DO appear in shareable
        // content — this explicit exclusion is the active feedback-loop
        // protection for the live-zoom stream.
```

- [ ] **Step 3: ScreenRecorderController**

`ZoomIt4Mac/Sources/ScreenRecorderController.swift`:
```swift
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
                    let session = micSession
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
        lock.lock()
        let hadContent = sessionStarted && !cancelled
        cancelled = true
        lock.unlock()
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
        lock.lock()
        cancelled = true
        lock.unlock()
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
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
```

- [ ] **Step 4: Build, regression, launch smoke**

Run: `xcodegen && xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build 2>&1 | tail -1 && xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED, TEST SUCCEEDED. Launch app ~5 s, no crash, pkill. (Recorder not yet wired — Task 4.)

- [ ] **Step 5: Commit**

```bash
git add ZoomIt4Mac project.yml
git commit -m "Add screen recorder controller and make overlays capturable"
```

---

### Task 4: Shell — coordinator wiring, indicator, menu

**Files:**
- Modify: `ZoomIt4Mac/Sources/SessionCoordinator.swift`, `ZoomIt4Mac/Sources/StatusItemController.swift`, `ZoomIt4Mac/Sources/AppDelegate.swift`

Shell task: build + regression + launch smoke.

**Interfaces:**
- Consumes: `ScreenRecording`/`ScreenRecorderController` (Task 3), `.startRecording/.stopRecording` effects + `isRecording` (Task 2)
- Produces: `SessionCoordinator.init(settings:snapshotter:permissions:liveStream:recorder:)`, `var onRecordingStateChange: ((Bool) -> Void)?`; `StatusItemController.setRecording(_ on: Bool)` + menu item title switching

- [ ] **Step 1: Coordinator**

`SessionCoordinator.swift`:
- Add `private let recorder: ScreenRecording` and an `recorder: ScreenRecording` init parameter (after `liveStream`); assign it.
- Add `var onRecordingStateChange: ((Bool) -> Void)?` and `private var lastReportedRecording = false`.
- At the tail of `send(_:)` (next to `syncBreakTickTimer()`):
```swift
        if machine.isRecording != lastReportedRecording {
            lastReportedRecording = machine.isRecording
            onRecordingStateChange?(machine.isRecording)
        }
```
- Replace the placeholder arms in `perform(_:)`:
```swift
        case .startRecording:
            startRecording()
        case .stopRecording:
            recorder.stop { url in
                if let url {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
```
- Add:
```swift
    private func startRecording() {
        guard permissions.hasScreenRecordingPermission() else {
            // Defer so the current effect batch finishes before the machine
            // unwinds; the system prompt is never hidden behind overlays.
            Task { @MainActor in
                self.permissions.requestPermission()
                self.send(.recordingFailed)
            }
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screen(containing: mouse) ?? NSScreen.main else {
            send(.recordingFailed)
            return
        }
        let recording = machine.settings.recording
        recorder.start(
            displayID: screen.displayID,
            microphone: recording.recordMicrophone,
            systemAudio: recording.recordSystemAudio,
            onError: { [weak self] _ in
                self?.send(.recordingFailed)
            }
        )
    }
```

- [ ] **Step 2: StatusItemController**

- Add init parameter `onRecord: @escaping () -> Void` (after `onBreak`), stored property, menu item after Break Timer:
```swift
        recordItem = makeItem("Start Recording", action: #selector(recordTapped), key: "5")
        menu.addItem(recordItem)
```
with `private var recordItem: NSMenuItem!` (create before `super.init()` constraints allow — build it in init after menu creation and keep the reference) and:
```swift
    @objc private func recordTapped() { onRecord() }
```
- Replace `setWarning` with combined state handling:
```swift
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
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        if recordingOn && !warningOn {
            image?.isTemplate = false // allow the red tint
            statusItem.button?.contentTintColor = .systemRed
        } else {
            statusItem.button?.contentTintColor = nil
        }
        statusItem.button?.image = image
    }
```

- [ ] **Step 3: AppDelegate**

- Pass the recorder: `liveStream: LiveStreamController(), recorder: ScreenRecorderController()` in the coordinator init.
- StatusItemController call gains `onRecord: { coordinator.trigger(.toggleRecord) }` (after onBreak).
- After creating both, wire the indicator:
```swift
        coordinator.onRecordingStateChange = { [weak self] recording in
            self?.statusItemController?.setRecording(recording)
        }
```

- [ ] **Step 4: Build, regression, launch smoke**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build 2>&1 | tail -1 && xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED, TEST SUCCEEDED. Launch, no crash, pkill.

- [ ] **Step 5: Commit**

```bash
git add ZoomIt4Mac
git commit -m "Wire screen recording into coordinator, status item, and menu"
```

---

### Task 5: Settings UI, shortcuts panel, README, verify

**Files:**
- Modify: `ZoomIt4Mac/Sources/SettingsWindow.swift`, `ZoomIt4Mac/Sources/ShortcutsWindow.swift`, `README.md`

Shell task: build + regression + launch smoke; full manual checklist is the human's.

- [ ] **Step 1: Settings**

Hotkeys section, after the Break Timer row:
```swift
                hotkeyRow("Recording", action: .toggleRecord)
```
New section after "Break Timer":
```swift
            Section("Recording") {
                Toggle("Record microphone", isOn: Binding(
                    get: { model.settings.recording.recordMicrophone },
                    set: { model.settings.recording.recordMicrophone = $0; model.save() }
                ))
                Text("macOS asks for microphone access the first time a recording starts with this enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Record system audio", isOn: Binding(
                    get: { model.settings.recording.recordSystemAudio },
                    set: { model.settings.recording.recordSystemAudio = $0; model.save() }
                ))
            }
```

- [ ] **Step 2: Shortcuts panel**

Global section, after the Break Timer row:
```swift
            Shortcut(keys: comboLabel(hotkeys.combo(for: .toggleRecord)), action: "Recording — start/stop recording the screen"),
```

- [ ] **Step 3: README**

Features, after the Break Timer bullet:
```markdown
- **Screen Recording** (`⌃5`) — start/stop recording the active display to `~/Movies/ZoomIt4Mac/` (H.264 .mp4, revealed in Finder when done). Your zoom and draw annotations are part of the recording. Optional microphone and system-audio capture (Settings → Recording); works while any other mode is active.
```
Permissions section, append:
```markdown
Recording with the microphone enabled additionally asks for **Microphone** permission (optional — recordings proceed without it if denied).
```

- [ ] **Step 4: Build, full suite, launch smoke**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build 2>&1 | tail -1 && xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED, TEST SUCCEEDED.

Manual smoke (human): ⌃5 → red menu-bar dot; menu shows "Stop Recording"; record desktop, then a session with ⌃1 zoom + draw — annotations visible in the saved file; stop → Finder reveals .mp4, plays in QuickTime; mic toggle produces narration track (first use prompts); system-audio toggle captures playing music; toggles persist; permission-missing paths degrade cleanly.

- [ ] **Step 5: Commit**

```bash
git add ZoomIt4Mac README.md
git commit -m "Add recording settings, shortcuts reference, and docs"
```
