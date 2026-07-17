# Recording Codec & Tuned Bitrate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut screen-recording file size ~40–50% via HEVC default + tuned bitrate, with an H.264 compatibility option in Settings.

**Architecture:** `RecordingCodec` enum + pure bitrate function live in `ZoomItCore` (`RecordingConfiguration.swift`) with migration + tests; the app shell threads the codec through the `ScreenRecording` protocol into `RecordingWriter`'s `AVVideoCompressionPropertiesKey`; SettingsWindow gets a picker. Spec: `docs/superpowers/specs/2026-07-17-recording-codec-design.md`.

**Tech Stack:** Swift 6, Swift Testing (core), AVFoundation/ScreenCaptureKit (shell), SwiftUI (settings).

## Global Constraints

- `ZoomItCore` must never import AppKit/AVFoundation — pure Swift only.
- No `Date`/`Timer` in core; no test may require TCC permissions or a display.
- Shell (`ZoomIt4Mac` target) has **no unit tests by design** — verified by build + interactive smoke.
- `ZoomIt4Mac.xcodeproj` is generated — do NOT edit it. No new files are added in this plan, so `xcodegen` regen is NOT needed.
- State-machine untouched; settings changes need `decodeIfPresent` migration + pinned migration test.
- Build: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build`
- Tests: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'`
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Core — `RecordingCodec` enum, `codec` field, migration

**Files:**
- Modify: `ZoomItCore/Sources/RecordingConfiguration.swift`
- Test: `ZoomItCore/Tests/RecordingConfigurationTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `public enum RecordingCodec: String, Codable, Equatable, Sendable { case hevc, h264 }`; `RecordingConfiguration.codec: RecordingCodec` (default `.hevc`); `public init(recordMicrophone: Bool, recordSystemAudio: Bool, codec: RecordingCodec = .hevc)`.

- [ ] **Step 1: Write the failing tests**

Append inside `struct RecordingConfigurationTests` in `ZoomItCore/Tests/RecordingConfigurationTests.swift`:

```swift
    @Test func defaultCodecIsHEVC() {
        #expect(RecordingConfiguration.default.codec == .hevc)
    }

    @Test func codecRoundTrip() throws {
        var c = RecordingConfiguration.default
        c.codec = .h264
        let back = try JSONDecoder().decode(RecordingConfiguration.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }

    // Migration: JSON persisted before the codec field existed must decode
    // with the HEVC default. Pinned — do not update this JSON literal.
    @Test func migratesLegacyJSONWithoutCodec() throws {
        let legacy = Data(#"{"recordMicrophone":false,"recordSystemAudio":true}"#.utf8)
        let c = try JSONDecoder().decode(RecordingConfiguration.self, from: legacy)
        #expect(!c.recordMicrophone)
        #expect(c.recordSystemAudio)
        #expect(c.codec == .hevc)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' -only-testing:ZoomItCoreTests/RecordingConfigurationTests
```
Expected: BUILD FAILS — `RecordingConfiguration` has no member `codec`, `RecordingCodec` not found. (Compile failure is the failing state for these tests.)

- [ ] **Step 3: Implement**

Replace the entire contents of `ZoomItCore/Sources/RecordingConfiguration.swift` with:

```swift
import Foundation

public enum RecordingCodec: String, Codable, Equatable, Sendable {
    case hevc
    case h264
}

public struct RecordingConfiguration: Codable, Equatable, Sendable {
    public var recordMicrophone: Bool
    public var recordSystemAudio: Bool
    public var codec: RecordingCodec

    enum CodingKeys: String, CodingKey {
        case recordMicrophone
        case recordSystemAudio
        case codec
    }

    public static let `default` = RecordingConfiguration(
        recordMicrophone: true,
        recordSystemAudio: false
    )

    public init(
        recordMicrophone: Bool,
        recordSystemAudio: Bool,
        codec: RecordingCodec = .hevc
    ) {
        self.recordMicrophone = recordMicrophone
        self.recordSystemAudio = recordSystemAudio
        self.codec = codec
    }

    // Migration: JSON persisted before the codec field existed has no codec key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordMicrophone = try container.decode(Bool.self, forKey: .recordMicrophone)
        recordSystemAudio = try container.decode(Bool.self, forKey: .recordSystemAudio)
        codec = try container.decodeIfPresent(RecordingCodec.self, forKey: .codec) ?? .hevc
    }
}
```

(Custom `init(from:)` suppresses the synthesized memberwise init, hence the explicit one. `encode(to:)` stays synthesized — all keys always encode.)

- [ ] **Step 4: Run tests to verify they pass**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' -only-testing:ZoomItCoreTests/RecordingConfigurationTests
```
Expected: all `RecordingConfigurationTests` PASS (including the pre-existing `defaults`, `codableRoundTrip`).

- [ ] **Step 5: Commit**

```sh
git add ZoomItCore/Sources/RecordingConfiguration.swift ZoomItCore/Tests/RecordingConfigurationTests.swift
git commit -m "Add RecordingCodec setting with HEVC default and migration

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Core — screen-content bitrate function

**Files:**
- Modify: `ZoomItCore/Sources/RecordingConfiguration.swift`
- Test: `ZoomItCore/Tests/RecordingConfigurationTests.swift`

**Interfaces:**
- Consumes: `RecordingCodec` from Task 1.
- Produces: `public func averageBitRate(width: Int, height: Int, frameRate: Int) -> Int` on `RecordingCodec`.

- [ ] **Step 1: Write the failing tests**

Append inside `struct RecordingConfigurationTests`:

```swift
    // 16" MacBook Pro Retina full screen: 3456×2234 @ 30 fps.
    // h264: 3456*2234*30 * 0.07 = 16_213_478.4 → 16_213_478
    // hevc: 3456*2234*30 * 0.04 =  9_264_844.8 →  9_264_845
    @Test func bitrateForRetinaFullScreen() {
        #expect(RecordingCodec.h264.averageBitRate(width: 3456, height: 2234, frameRate: 30) == 16_213_478)
        #expect(RecordingCodec.hevc.averageBitRate(width: 3456, height: 2234, frameRate: 30) == 9_264_845)
    }

    @Test func bitrateClampsToFloor() {
        // 100×100 @ 30 fps is far below the 1 Mbps floor for both codecs.
        #expect(RecordingCodec.h264.averageBitRate(width: 100, height: 100, frameRate: 30) == 1_000_000)
        #expect(RecordingCodec.hevc.averageBitRate(width: 100, height: 100, frameRate: 30) == 1_000_000)
    }

    @Test func bitrateFloorOnDegenerateInput() {
        #expect(RecordingCodec.hevc.averageBitRate(width: 0, height: 0, frameRate: 30) == 1_000_000)
        #expect(RecordingCodec.h264.averageBitRate(width: -100, height: 100, frameRate: 30) == 1_000_000)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' -only-testing:ZoomItCoreTests/RecordingConfigurationTests
```
Expected: BUILD FAILS — `averageBitRate` not found on `RecordingCodec`.

- [ ] **Step 3: Implement**

Append to `ZoomItCore/Sources/RecordingConfiguration.swift`:

```swift
extension RecordingCodec {
    /// Average bitrate for screen-content encoding. Screen content (flat
    /// regions, static areas, sharp edges) compresses far better than camera
    /// video, so these bits-per-pixel targets stay visually lossless while
    /// roughly halving VideoToolbox's dimension-scaled default.
    public func averageBitRate(width: Int, height: Int, frameRate: Int) -> Int {
        let bitsPerPixel: Double
        switch self {
        case .h264: bitsPerPixel = 0.07
        case .hevc: bitsPerPixel = 0.04
        }
        let raw = Double(width) * Double(height) * Double(frameRate) * bitsPerPixel
        return max(1_000_000, Int(raw.rounded()))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' -only-testing:ZoomItCoreTests/RecordingConfigurationTests
```
Expected: all PASS.

- [ ] **Step 5: Run the full core suite**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'
```
Expected: all tests PASS (Settings roundtrip etc. unaffected — `codec` always encodes).

- [ ] **Step 6: Commit**

```sh
git add ZoomItCore/Sources/RecordingConfiguration.swift ZoomItCore/Tests/RecordingConfigurationTests.swift
git commit -m "Add screen-content bitrate targets per recording codec

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Shell — thread codec into recorder, tuned compression properties

**Files:**
- Modify: `ZoomIt4Mac/Sources/ScreenRecorderController.swift`
- Modify: `ZoomIt4Mac/Sources/SessionCoordinator.swift:425-434` (`beginRecording`)

**Interfaces:**
- Consumes: `RecordingCodec`, `averageBitRate(width:height:frameRate:)` from Tasks 1–2; `RecordingConfiguration.codec`.
- Produces: `ScreenRecording.start(displayID:codec:microphone:systemAudio:onError:)` — new `codec: RecordingCodec` parameter, second position.

- [ ] **Step 1: Extend the `ScreenRecording` protocol**

In `ZoomIt4Mac/Sources/ScreenRecorderController.swift`, replace the protocol:

```swift
@MainActor
protocol ScreenRecording: AnyObject {
    func start(
        displayID: CGDirectDisplayID,
        codec: RecordingCodec,
        microphone: Bool,
        systemAudio: Bool,
        onError: @escaping @MainActor (CaptureFailure) -> Void
    )
    func stop(completion: @escaping @MainActor (URL?) -> Void)
}
```

- [ ] **Step 2: Thread codec through `ScreenRecorderController.start`**

Same file — add `codec: RecordingCodec,` to `start`'s parameter list (after `displayID`), and pass it to the writer. The `RecordingWriter` construction becomes:

```swift
                let url = try Self.makeOutputURL()
                let writer = try RecordingWriter(
                    url: url,
                    videoSize: pixelSize,
                    codec: codec,
                    systemAudio: systemAudio,
                    microphone: micEnabled
                )
```

- [ ] **Step 3: Tuned compression settings in `RecordingWriter`**

Same file — change `RecordingWriter.init`'s signature to
`init(url: URL, videoSize: CGSize, codec: RecordingCodec, systemAudio: Bool, microphone: Bool) throws`
and replace the `videoSettings` block:

```swift
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
```

Container stays `.mp4` — AVFoundation writes HEVC with the `hvc1` tag, playable in QuickTime/Photos/Finder previews.

- [ ] **Step 4: Pass the codec from `SessionCoordinator`**

In `ZoomIt4Mac/Sources/SessionCoordinator.swift`, `beginRecording` becomes:

```swift
    private func beginRecording(displayID: CGDirectDisplayID, recording: RecordingConfiguration) {
        recorder.start(
            displayID: displayID,
            codec: recording.codec,
            microphone: recording.recordMicrophone,
            systemAudio: recording.recordSystemAudio,
            onError: { [weak self] _ in
                self?.send(.recordingFailed)
            }
        )
    }
```

- [ ] **Step 5: Build**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build
```
Expected: BUILD SUCCEEDED. If the compiler flags any other `ScreenRecording` conformer or `recorder.start` call site missed above, update it the same way (add `codec:`).

- [ ] **Step 6: Commit**

```sh
git add ZoomIt4Mac/Sources/ScreenRecorderController.swift ZoomIt4Mac/Sources/SessionCoordinator.swift
git commit -m "Encode recordings with selected codec and tuned bitrate

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Settings UI — video codec picker

**Files:**
- Modify: `ZoomIt4Mac/Sources/SettingsWindow.swift:253-265` (Recording section)

**Interfaces:**
- Consumes: `RecordingCodec`, `settings.recording.codec` from Task 1.
- Produces: user-visible picker; no code interface.

- [ ] **Step 1: Add the picker**

In the `Section("Recording")` block, after the "Record system audio" toggle (line ~264), add:

```swift
                Picker("Video codec", selection: Binding(
                    get: { model.settings.recording.codec },
                    set: { model.settings.recording.codec = $0; model.save() }
                )) {
                    Text("HEVC (smaller files)").tag(RecordingCodec.hevc)
                    Text("H.264 (most compatible)").tag(RecordingCodec.h264)
                }
```

(`SettingsWindow.swift` already imports `ZoomItCore`; the binding get/set + `model.save()` pattern matches the surrounding toggles.)

- [ ] **Step 2: Build**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```sh
git add ZoomIt4Mac/Sources/SettingsWindow.swift
git commit -m "Add video codec picker to recording settings

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Full test run + interactive smoke

**Files:** none (verification only).

- [ ] **Step 1: Full suite**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'
```
Expected: all tests PASS.

- [ ] **Step 2: Interactive smoke (needs the user — screen-recording TCC + display)**

Ask the user to run this pass and report back:

1. Launch the app, open Settings → Recording. Verify "Video codec" picker shows **HEVC (smaller files)** selected by default.
2. Record ~30 s of full-screen activity (⌃5 start/stop) with HEVC. Note the file size in `~/Movies/ZoomIt4Mac/`.
3. Switch the picker to **H.264 (most compatible)**; record the same ~30 s again. Note size.
4. Expected: HEVC file roughly half the size of pre-change recordings (compare against an older recording if one exists); H.264 also smaller than before; both play in QuickTime with audio intact and cursor visible; Finder preview thumbnails render for the HEVC file.
5. Quit + relaunch the app: codec choice persists.

- [ ] **Step 3: Record smoke results**

Document the smoke outcome (sizes observed, playback OK) in the PR description — shell behavior changes get an interactive smoke pass instead of unit tests per CLAUDE.md.
